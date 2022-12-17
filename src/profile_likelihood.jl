const dict_lock = ReentrantLock()

function profile(prob::LikelihoodProblem, sol::LikelihoodSolution, n=1:number_of_parameters(prob);
    alg=get_optimiser(sol),
    conf_level::F=0.95,
    confidence_interval_method=:spline,
    threshold=get_chisq_threshold(conf_level),
    resolution=200,
    param_ranges=construct_profile_ranges(sol, get_lower_bounds(prob), get_upper_bounds(prob), resolution),
    min_steps=10,
    normalise::Bool=true,
    spline_alg=FritschCarlsonMonotonicInterpolation,
    extrap=Line,
    parallel=false,
    kwargs...) where {F}
    ## Extract the problem and solution 
    opt_prob, mles, ℓmax = extract_problem_and_solution(prob, sol)

    ## Prepare the profile results 
    N = length(n)
    T = number_type(mles)
    θ, prof, other_mles, splines, confidence_intervals = prepare_profile_results(N, T, F, spline_alg, extrap)

    ## Normalise the objective function 
    shifted_opt_prob = normalise_objective_function(opt_prob, ℓmax, normalise)

    ## Loop over each parameter 
    num_params = number_of_parameters(shifted_opt_prob)
    if !parallel
        for _n in n
            profile_single_parameter!(θ, prof, other_mles, splines, confidence_intervals,
                _n, num_params, param_ranges, mles,
                shifted_opt_prob, alg, ℓmax, normalise, threshold, min_steps,
                spline_alg, extrap, confidence_interval_method, conf_level; parallel, kwargs...)
        end
    else
        @sync for _n in n
            Base.Threads.@spawn profile_single_parameter!(θ, prof, other_mles, splines, confidence_intervals,
                _n, num_params, param_ranges, deepcopy(mles),
                deepcopy(shifted_opt_prob), alg, deepcopy(ℓmax), normalise, threshold, min_steps,
                spline_alg, extrap, confidence_interval_method, conf_level; parallel, kwargs...)
        end
    end
    # splines = Dict(keys(splines) .=> values(splines)) # fixes the type 
    return ProfileLikelihoodSolution(θ, prof, prob, sol, splines, confidence_intervals, other_mles)
end

function profile_single_parameter!(θ, prof, other_mles, splines, confidence_intervals,
    n, num_params, param_ranges, mles,
    shifted_opt_prob, alg, ℓmax, normalise, threshold, min_steps,
    spline_alg, extrap, confidence_interval_method, conf_level; parallel=false, kwargs...)
    ## First, prepare all the cache vectors  
    _param_ranges = param_ranges[n]
    left_profile_vals, right_profile_vals,
    left_param_vals, right_param_vals,
    left_other_mles, right_other_mles,
    combined_profiles, combined_param_vals, combined_other_mles,
    cache, sub_cache = prepare_cache_vectors(n, num_params, _param_ranges, mles)
    sub_cache_left, sub_cache_right = deepcopy(sub_cache), deepcopy(sub_cache)

    ## Now restrict the problem 
    restricted_prob_left = exclude_parameter(deepcopy(shifted_opt_prob), n)
    restricted_prob_right = exclude_parameter(deepcopy(shifted_opt_prob), n)
    restricted_prob_left.u0 .= sub_cache_left
    restricted_prob_right.u0 .= sub_cache_right

    if !parallel
        ## Get the left endpoint
        find_endpoint!(left_param_vals, left_profile_vals, left_other_mles, _param_ranges[1],
            restricted_prob_left, n, cache, alg, sub_cache_left, ℓmax, normalise,
            threshold, min_steps, mles; kwargs...)

        ## Get the right endpoint
        find_endpoint!(right_param_vals, right_profile_vals, right_other_mles, _param_ranges[2],
            restricted_prob_right, n, cache, alg, sub_cache_right, ℓmax, normalise,
            threshold, min_steps, mles; kwargs...)
    else
        ## Get the left endpoint
        @sync begin
            @async find_endpoint!(left_param_vals, left_profile_vals, left_other_mles, _param_ranges[1],        #=left_end = Base.Threads.@spawn=#
                restricted_prob_left, n, cache, alg, sub_cache_left, ℓmax, normalise,
                threshold, min_steps, mles; kwargs...)

            ## Get the right endpoint
            @async find_endpoint!(right_param_vals, right_profile_vals, right_other_mles, _param_ranges[2],        #=right_end = Base.Threads.@spawn=#
                restricted_prob_right, n, cache, alg, sub_cache_right, ℓmax, normalise,
                threshold, min_steps, mles; kwargs...)
        end
    end

    ## Now combine the results 
    combine_and_clean_results!(left_profile_vals, right_profile_vals,
        left_param_vals, right_param_vals,
        left_other_mles, right_other_mles,
        combined_profiles, combined_param_vals, combined_other_mles)

    ## Put the results in 
    lock(dict_lock) do
        θ[n] = combined_param_vals
        prof[n] = combined_profiles
        other_mles[n] = combined_other_mles
    end

    # Put a spline through the profile 
    spline_profile!(splines, n, combined_param_vals, combined_profiles, spline_alg, extrap)

    ## Get the confidence intervals
    get_confidence_intervals!(confidence_intervals, confidence_interval_method,
        n, combined_param_vals, combined_profiles, threshold, spline_alg, extrap, mles, conf_level)
    return nothing
end

function construct_profile_ranges(lower_bound, upper_bound, midpoint, resolution)
    if ⊻(isinf(lower_bound), isinf(upper_bound))
        throw("The provided parameter bounds must be finite.")
    end
    left_range = LinRange(midpoint, lower_bound, resolution)
    right_range = LinRange(midpoint, upper_bound, resolution)
    param_ranges = (left_range, right_range)
    return param_ranges
end
function construct_profile_ranges(sol::LikelihoodSolution{N,Θ,P,M,R,A}, lower_bounds, upper_bounds, resolutions) where {N,Θ,P,M,R,A}
    param_ranges = Vector{NTuple{2,LinRange{Float64,Int64}}}(undef, number_of_parameters(sol))
    mles = get_mle(sol)
    for i in 1:N
        param_ranges[i] = construct_profile_ranges(lower_bounds[i], upper_bounds[i], mles[i], resolutions isa Number ? resolutions : resolutions[i])
    end
    return param_ranges
end

function extract_problem_and_solution(prob::LikelihoodProblem, sol::LikelihoodSolution)
    opt_prob = get_problem(prob)
    mles = deepcopy(get_mle(sol)) 
    ℓmax = get_maximum(sol)
    return opt_prob, mles, ℓmax
end

function prepare_profile_results(N, T, F, spline_alg=FritschCarlsonMonotonicInterpolation, extrap=Line)
    θ = Dict{Int64,Vector{T}}([])
    prof = Dict{Int64,Vector{T}}([])
    other_mles = Dict{Int64,Vector{Vector{T}}}([])
    if typeof(spline_alg) <: Gridded
        spline_type = typeof(extrapolate(interpolate((T.(collect(1:20)),), T.(collect(1:20)), spline_alg isa Type ? spline_alg() : spline_alg), extrap isa Type ? extrap() : extrap))
    else
        spline_type = typeof(extrapolate(interpolate(T.(collect(1:20)), T.(collect(1:20)), spline_alg isa Type ? spline_alg() : spline_alg), extrap isa Type ? extrap() : extrap))
    end
    splines = Dict{Int64,spline_type}([])
    confidence_intervals = Dict{Int64,ConfidenceInterval{T,F}}([])
    sizehint!(θ, N)
    sizehint!(prof, N)
    sizehint!(other_mles, N)
    sizehint!(splines, N)
    sizehint!(confidence_intervals, N)
    return θ, prof, other_mles, splines, confidence_intervals
end

function normalise_objective_function(opt_prob, ℓmax, normalise::Bool)
    shifted_opt_prob = normalise ? shift_objective_function(opt_prob, -ℓmax) : opt_prob
    return shifted_opt_prob
end

function reset_profile_vectors!(restricted_prob, param_vals, profile_vals, other_mles, min_steps, mles, n)
    restricted_prob.u0 .= mles[Not(n)]
    new_range = LinRange(param_vals[1], param_vals[end], min_steps)
    !isempty(param_vals) && empty!(param_vals)
    !isempty(profile_vals) && empty!(profile_vals)
    !isempty(other_mles) && empty!(other_mles)
    return new_range
end

function reset_find_endpoint!(param_vals, profile_vals, other_mles, param_range,
    restricted_prob, n, cache, alg, sub_cache, ℓmax, normalise,
    threshold, min_steps, mles; kwargs...)
    sub_cache .= mles[Not(n)]
    new_range = reset_profile_vectors!(restricted_prob, param_vals, profile_vals, other_mles, min_steps, mles, n)
    find_endpoint!(param_vals, profile_vals, other_mles, new_range,
        restricted_prob, n, cache, alg, sub_cache, ℓmax, normalise,
        typemin(threshold), zero(min_steps), mles; kwargs...)
    return nothing
end

function find_endpoint!(param_vals, profile_vals, other_mles, param_range,
    restricted_prob, n, cache, alg, sub_cache, ℓmax, normalise,
    threshold, min_steps, mles; kwargs...)
    steps = 1
    for θₙ in param_range
        push!(param_vals, θₙ)
        ## Fix the objective function 
        fixed_prob = construct_fixed_optimisation_function(restricted_prob, n, θₙ, cache)
        fixed_prob.u0 .= sub_cache
        ## Solve the fixed problem 
        soln = solve(fixed_prob, alg; kwargs...)
        sub_cache .= soln.u
        push!(profile_vals, -soln.minimum - ℓmax * !normalise)
        push!(other_mles, soln.u)
        ## Increment 
        steps += 1
        if profile_vals[end] ≤ threshold
            break
        end
    end
    ## Check if we need to extend the values 
    if steps ≤ min_steps
        reset_find_endpoint!(param_vals, profile_vals, other_mles, param_range,
            restricted_prob, n, cache, alg, sub_cache, ℓmax, normalise,
            threshold, min_steps, mles; kwargs...)
    end
    return nothing
end

function prepare_cache_vectors(n, num_params, param_ranges, mles::AbstractVector{T}) where {T}
    left_profile_vals = Vector{T}([])
    right_profile_vals = Vector{T}([])
    left_param_vals = Vector{T}([])
    right_param_vals = Vector{T}([])
    left_other_mles = Vector{Vector{T}}([])
    right_other_mles = Vector{Vector{T}}([])
    combined_profiles = Vector{T}([])
    combined_param_vals = Vector{T}([])
    combined_other_mles = Vector{Vector{T}}([])
    sizehint!(left_profile_vals, length(param_ranges[1]))
    sizehint!(right_profile_vals, length(param_ranges[2]))
    sizehint!(combined_profiles, length(param_ranges[1]) + length(param_ranges[2]))
    sizehint!(combined_param_vals, length(param_ranges[1]) + length(param_ranges[2]))
    sizehint!(combined_other_mles, length(param_ranges[1]) + length(param_ranges[2]))
    cache = DiffCache(zeros(T, num_params))
    sub_cache = zeros(T, num_params - 1)
    sub_cache .= mles[Not(n)]
    return left_profile_vals, right_profile_vals,
    left_param_vals, right_param_vals,
    left_other_mles, right_other_mles,
    combined_profiles, combined_param_vals, combined_other_mles,
    cache, sub_cache
end

function combine_and_clean_results!(left_profile_vals, right_profile_vals,
    left_param_vals, right_param_vals,
    left_other_mles, right_other_mles,
    combined_profiles, combined_param_vals, combined_other_mles)
    ## Combine the results 
    append!(combined_profiles, left_profile_vals, right_profile_vals)
    append!(combined_param_vals, left_param_vals, right_param_vals)
    append!(combined_other_mles, left_other_mles, right_other_mles)

    ## Make sure the results are sorted 
    sort_idx = sortperm(combined_param_vals)
    permute!(combined_param_vals, sort_idx)
    permute!(combined_profiles, sort_idx)
    permute!(combined_other_mles, sort_idx)

    ## Cleanup some duplicate values
    idx = unique(i -> combined_param_vals[i], eachindex(combined_param_vals))
    keepat!(combined_param_vals, idx)
    keepat!(combined_profiles, idx)
    keepat!(combined_other_mles, idx)
    return nothing
end

function spline_profile!(splines, n, param_vals, profiles, spline_alg, extrap)
    try
        if typeof(spline_alg) <: Gridded
            itp = interpolate((param_vals,), profiles, spline_alg isa Type ? spline_alg() : spline_alg)
            splines[n] = extrapolate(itp, extrap isa Type ? extrap() : extrap)
        else
            itp = interpolate(param_vals, profiles, spline_alg isa Type ? spline_alg() : spline_alg)
            splines[n] = extrapolate(itp, extrap isa Type ? extrap() : extrap)
        end
    catch e
        @show e
        error("Error creating the spline. Try increasing the grid resolution for parameter $n or increasing min_steps.")
    end
    return nothing
end

function get_confidence_intervals!(confidence_intervals, method, n, param_vals, profile_vals, threshold, spline_alg, extrap, mles, conf_level)
    if method == :spline
        try
            _get_confidence_intervals_spline!(confidence_intervals, n, param_vals, profile_vals, threshold, spline_alg, extrap, mles, conf_level)
        catch
            @warn("Failed to create the confidence interval for parameter $n using a spline. Restarting using the extrema method.")
            get_confidence_intervals!(confidence_intervals, :extrema, n, param_vals, profile_vals, threshold, spline_alg, extrap, mles, conf_level)
        end
    elseif method == :extrema
        try
            _get_confidence_intervals_extrema!(confidence_intervals, n, param_vals, profile_vals, threshold, conf_level)
        catch
            @warn("Failed to create the confidence interval for parameter $n.")
            confidence_intervals[n] = ConfidenceInterval(NaN, NaN, conf_level)
        end
    end
    return nothing
end
function _get_confidence_intervals_spline!(confidence_intervals, n, param_vals, combined_profiles, threshold, spline_alg, extrap, mles, conf_level)
    itp = interpolate(param_vals, combined_profiles .- threshold, spline_alg isa Type ? spline_alg() : spline_alg)
    itp_f = (θ, _) -> itp(θ)
    left_bracket = (param_vals[begin], mles[n])
    right_bracket = (mles[n], param_vals[end])
    left_prob = IntervalNonlinearProblem(itp_f, left_bracket)
    right_prob = IntervalNonlinearProblem(itp_f, right_bracket)
    ℓ = solve(left_prob, Falsi()).u
    u = solve(right_prob, Falsi()).u
    confidence_intervals[n] = ConfidenceInterval(ℓ, u, conf_level)
    return nothing
end
function _get_confidence_intervals_extrema!(confidence_intervals, n, param_vals, profile_vals, threshold, conf_level)
    conf_region = profile_vals .≥ threshold
    idx = findall(conf_region)
    ab = extrema(param_vals[idx])
    try
        confidence_intervals[n] = ConfidenceInterval(ab..., conf_level)
    catch
        @warn("Failed to find a valid confidence interval for parameter $n. Returning the extrema of the parameter values.")
        confidence_intervals[n] = ConfidenceInterval(extrema(param_vals[n])..., conf_level)
    end
end
