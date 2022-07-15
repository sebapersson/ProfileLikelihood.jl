"""
    construct_new_f(prob::OptimizationProblem, i, val, cache::PreallocationTools.DiffCache)
    construct_new_f(prob::OptimizationProblem, i, val, cache::AbstractVector) 

Given `prob`, computes a new objective function which fixes the `i`th variable at the value `val`. 
`cache` is used to store the variables along with this fixed value.
"""
function construct_new_f end
@doc (@doc construct_new_f) @inline function construct_new_f(prob::OptimizationProblem, i, val, cache::PreallocationTools.DiffCache)
    new_f = @inline (θ, p) -> begin
        cache2 = get_tmp(cache, θ)
        cache2[Not(i)] .= θ
        cache2[i] = val
        return prob.f(cache2, p)
    end
    return new_f
end
@doc (@doc construct_new_f) @inline function construct_new_f(prob::OptimizationProblem, i, val, cache::AbstractVector)
    new_f = @inline (θ, p) -> begin
        cache[Not(i)] .= θ
        cache[i] = val
        return prob.f(cache, p)
    end
    return new_f
end

"""
    [1] update_prob(prob::OptimizationProblem{iip,F,uType,P,B,LC,UC,S,K}, i::Int) where {iip,F,uType,P,B<:AbstractVector,LC,UC,S,K}
    [2] update_prob(prob::OptimizationProblem{iip,F,uType,P,Nothing,LC,UC,S,K}) where {iip,F,uType,P,LC,UC,S,K}
    [3] update_prob(prob::OptimizationProblem, u0::AbstractVector) 
    [4] update_prob(prob::OptimizationProblem, i, val, cache) 
    [5] update_prob(prob::OptimizationProblem, i, val, cache, u0)

Given the [`OptimizationProblem`](@ref) `prob`, updates it based on the methods above.

1, 2. Removes the `i`th entry of the lower and upper bounds. The second method is used in case no bounds were provided.
   3. Updates the problem with a new initial guess `u0`.
   4. Replaces the objective function with a new one that fixes the `i`th variable at the value `val`. `cache` is used to store the variables along with this fixed value. 
   5. Performs method 4 and method 3.

These updates are not done in-place.
"""
function update_prob end
@inline function update_prob(prob::OptimizationProblem{iip,FF,θType,P,B,LC,UC,Sns,K}, i::Int) where {iip,AD,G,H,HV,C,CJ,CH,HP,CJP,CHP,S,HCV,CJCV,CHCV,EX,CEX,F,FF<:OptimizationFunction{iip,AD,F,G,H,HV,C,CJ,CH,HP,CJP,CHP,S,HCV,CJCV,CHCV,EX,CEX},θType,P,B,LC,UC,Sns,K}
    return remake(prob; lb=prob.lb[Not(i)], ub=prob.ub[Not(i)])
end
@inline function update_prob(prob::OptimizationProblem{iip,FF,θType,P,Nothing,LC,UC,Sns,K}, i::Int) where {iip,AD,G,H,HV,C,CJ,CH,HP,CJP,CHP,S,HCV,CJCV,CHCV,EX,CEX,F,FF<:OptimizationFunction{iip,AD,F,G,H,HV,C,CJ,CH,HP,CJP,CHP,S,HCV,CJCV,CHCV,EX,CEX},θType,P,LC,UC,Sns,K}
    prob
end
@inline function update_prob(prob::OptimizationProblem, u0::AbstractVector)
    return remake(prob; u0=u0)
end
@inline function update_prob(prob::OptimizationProblem{iip,FF,θType,P,B,LC,UC,Sns,K}, i, val, cache) where {iip,AD,G,H,HV,C,CJ,CH,HP,CJP,CHP,S,HCV,CJCV,CHCV,EX,CEX,F,FF<:OptimizationFunction{iip,AD,F,G,H,HV,C,CJ,CH,HP,CJP,CHP,S,HCV,CJCV,CHCV,EX,CEX},θType,P,B,LC,UC,Sns,K}
    new_f = construct_new_f(prob, i, val, cache)#didn't use to have all the type signatures above ^ but it's needed for type stability. Without them, this function runs in about 1.410 μs with 2.52 KiB memory (8 allocs), but with them it's 32.897 ns and 0 bytes (~42x change). Amazing!
    f = OptimizationFunction{iip,AD,typeof(new_f),G,H,HV,C,CJ,CH,HP,CJP,CHP,S,HCV,CJCV,CHCV,EX,CEX
    }(new_f,
        prob.f.adtype, prob.f.grad,
        prob.f.hess, prob.f.hv,
        prob.f.cons, prob.f.cons_j, prob.f.cons_h,
        prob.f.hess_prototype, prob.f.cons_jac_prototype, prob.f.cons_hess_prototype,
        prob.f.syms,
        prob.f.hess_colorvec, prob.f.cons_jac_colorvec, prob.f.cons_hess_colorvec,
        prob.f.expr, prob.f.cons_expr)
    return remake(prob; f=f)
end
@inline function update_prob(prob::OptimizationProblem, i, val, cache, u0)
    prob = update_prob(prob, i, val, cache)
    prob = update_prob(prob, u0)
    return prob
end

"""
    update_prob(prob::LikelihoodProblem, u0::AbstractVector)
    update_prob(prob::LikelihoodProblem, sol::LikelihoodSolution)

Update the `prob` with the new initial guess `u0`, or the MLEs from `sol`.
"""
@inline function update_prob(prob::LikelihoodProblem, u0::AbstractVector)
    optprob = prob.prob 
    prob_newu0 = update_prob(optprob, u0)
    prob = remake(prob; prob = prob_newu0, θ₀ = u0)
    return prob
end
@inline function update_prob(prob::LikelihoodProblem, sol::LikelihoodSolution)
    return update_prob(prob, mle(sol))
end
