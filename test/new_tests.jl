using ProfileLikelihood
using Test
using FiniteDiff
using Optimization
using OrdinaryDiffEq
using OptimizationNLopt
using OptimizationBBO
using Optimization: OptimizationProblem
using FunctionWrappers
using LinearAlgebra
using PreallocationTools
using Interpolations
using InvertedIndices
using Random
using Distributions
using OptimizationOptimJL
using CairoMakie
using LaTeXStrings
using LatinHypercubeSampling
using FiniteVolumeMethod
using DelaunayTriangulation
using LinearSolve
using SciMLBase
using MuladdMacro
using Base.Threads
using LoopVectorization
const PL = ProfileLikelihood
global SAVE_FIGURE = false

######################################################
## Templates 
######################################################
function multiple_linear_regression()
    Random.seed!(98871)
    n = 300
    β = [-1.0, 1.0, 0.5, 3.0]
    σ = 0.05
    θ₀ = ones(5)
    x₁ = rand(Uniform(-1, 1), n)
    x₂ = rand(Normal(1.0, 0.5), n)
    X = hcat(ones(n), x₁, x₂, x₁ .* x₂)
    ε = rand(Normal(0.0, σ), n)
    y = X * β + ε
    sse = DiffCache(zeros(n))
    β_cache = DiffCache(similar(β), 10)
    dat = (y, X, sse, n, β_cache)
    @inline function loglik(θ, data)
        local σ, y, X, sse, n, β # type stability
        σ, β₀, β₁, β₂, β₃ = θ
        y, X, sse, n, β = data
        sse = get_tmp(sse, θ)
        β = get_tmp(β, θ)
        β[1] = β₀
        β[2] = β₁
        β[3] = β₂
        β[4] = β₃
        ℓℓ = -0.5n * log(2π * σ^2)
        mul!(sse, X, β)
        for i in eachindex(y)
            ℓℓ = ℓℓ - 0.5 / σ^2 * (y[i] - sse[i])^2
        end
        return ℓℓ
    end
    prob = LikelihoodProblem(loglik, θ₀;
        data=dat,
        f_kwargs=(adtype=Optimization.AutoForwardDiff(),),
        prob_kwargs=(lb=[0.0, -Inf, -Inf, -Inf, -Inf],
            ub=Inf * ones(5)))
    @inferred loglik(prob.θ₀, ProfileLikelihood.get_data(prob))
    @inferred prob.problem.f(prob.θ₀, ProfileLikelihood.get_data(prob))
    return prob, loglik, [σ, β], dat
end

######################################################
## Utilities 
######################################################
## number_type 
x = 5.0
@test PL.number_type(x) == Float64
x = 5.0f0
@test PL.number_type(x) == Float32

x = [[5.0, 2.0], [2.0], [5.0, 5.0]]
@test PL.number_type(x) == Float64
x = [[[[[[[[[[[[[5.0]]]]]]]]]]]]]
@test PL.number_type(x) == Float64
x = [[2, 3, 4], [2, 3, 5]]
@test PL.number_type(x) == Int64

x = rand(5, 8)
@test PL.number_type(x) == Float64

x = ((5.0, 3.0), (2.0, 3.0), (5.0, 1.0))
@test PL.number_type(x) == Float64

x = ((5, 3), (2, 3), (5, 1), (2, 5))
@test PL.number_type(x) == Int64

## get_default_extremum
@test PL.get_default_extremum(Float64, Val{false}) == typemin(Float64)
@test PL.get_default_extremum(Float64, Val{true}) == typemax(Float64)
@test PL.get_default_extremum(Float32, Val{false}) == typemin(Float32)
@test PL.get_default_extremum(Float32, Val{true}) == typemax(Float32)

## update_extrema! 
new_x = zeros(4)
new_f = 2.0
old_x = [1.0, 2.0, 3.0, 4.0]
old_f = 1.0
new_f = PL.update_extremum!(new_x, new_f, old_x, old_f; minimise=Val(false))
@test new_f == 2.0
@test new_x == old_x

new_x = zeros(4)
new_f = 0.5
old_x = [1.0, 2.0, 3.0, 4.0]
old_f = 1.0
new_f = PL.update_extremum!(new_x, new_f, old_x, old_f; minimise=Val(false))
@test new_f == 1.0
@test new_x == zeros(4)

new_x = zeros(4)
new_f = 0.5
old_x = [1.0, 2.0, 3.0, 4.0]
old_f = 1.0
new_f = PL.update_extremum!(new_x, new_f, old_x, old_f; minimise=Val(true))
@test new_f == 0.5
@test new_x == old_x

new_x = zeros(4)
new_f = 1.5
old_x = [1.0, 2.0, 3.0, 4.0]
old_f = 1.0
new_f = PL.update_extremum!(new_x, new_f, old_x, old_f; minimise=Val(true))
@test new_f == 1.0
@test new_x == zeros(4)

## gaussian_loglikelihood
for _ in 1:250
    n = rand(1:500)
    x = rand(n)
    μ = rand(n)
    σ = 5rand()
    ℓ = 0.0
    for i in 1:n
        ℓ = ℓ - log(sqrt(2π * σ^2)) - (x[i] - μ[i])^2 / (2σ^2)
    end
    @test ℓ ≈ PL.gaussian_loglikelihood(x, μ, σ, n)
    @inferred PL.gaussian_loglikelihood(x, μ, σ, n)
end

## get_chisq_threshold
@test all(x -> PL.get_chisq_threshold(x) ≈ -0.5quantile(Chisq(1), x), 0.001:0.001:0.999)
@test all(x -> PL.get_chisq_threshold(x, 3) ≈ -0.5quantile(Chisq(3), x), 0.001:0.001:0.999)

## subscriptnumber
@test PL.subscriptnumber(1) == "₁"
@test PL.subscriptnumber(2) == "₂"
@test PL.subscriptnumber(3) == "₃"
@test PL.subscriptnumber(4) == "₄"
@test PL.subscriptnumber(5) == "₅"
@test PL.subscriptnumber(6) == "₆"
@test PL.subscriptnumber(7) == "₇"
@test PL.subscriptnumber(13) == "₁₃"

######################################################
## Problem updates
######################################################
## Test that we can correctly update the initial estimate 
loglik = (θ, p) -> θ[1] * p[1] + θ[2]
negloglik = PL.negate_loglik(loglik)
θ₀ = rand(3)
data = (rand(100), [:a, :b])
prob = PL.construct_optimisation_problem(negloglik, θ₀, data)
θ₁ = [0.0, 1.0, 0.0]
new_prob = PL.update_initial_estimate(prob, θ₁)
@test new_prob.u0 == θ₁
sol = solve(prob, Opt(:LN_NELDERMEAD, 3))
new_prob_2 = PL.update_initial_estimate(prob, sol)
@test new_prob_2.u0 == sol.u
@test prob.u0 == θ₀ # check aliasing

## Test that we are correctly replacing the objective function 
loglik = (θ, p) -> θ[1] * p[1] + θ[2]
negloglik = PL.negate_loglik(loglik)
θ₀ = rand(3)
data = (rand(100), [:a, :b])
prob = PL.construct_optimisation_problem(negloglik, θ₀, data)
new_obj = (θ, p) -> θ[1] * p[1] + θ[2] + p[2]
new_prob = PL.replace_objective_function(prob, new_obj)
@test collect(typeof(new_prob).parameters)[Not(2)] == collect(typeof(prob).parameters)[Not(2)]
@test collect(typeof(new_prob.f).parameters)[Not(3)] == collect(typeof(prob.f).parameters)[Not(3)]
@test new_prob.f.f == new_obj
@inferred PL.replace_objective_function(prob, new_obj)

## Test that we are correctly constructing a fixed function 
loglik = (θ, p) -> θ[1] * p[1] + θ[2]
negloglik = PL.negate_loglik(loglik)
θ₀ = rand(2)
data = 1.301
prob = PL.construct_optimisation_problem(negloglik, θ₀, data)
val = 1.0
n = 1
cache = DiffCache(θ₀)
new_f = PL.construct_fixed_optimisation_function(prob, n, val, cache)
@inferred PL.construct_fixed_optimisation_function(prob, n, val, cache)
@test new_f.f([2.31], data) ≈ negloglik([val, 2.31], data)
@inferred new_f.f([2.31], data)
cache = [1.0, 2.0]
new_f = PL.construct_fixed_optimisation_function(prob, n, val, cache)
@inferred PL.construct_fixed_optimisation_function(prob, n, val, cache)

val = 2.39291
n = 2
cache = DiffCache(θ₀)
new_f = PL.construct_fixed_optimisation_function(prob, n, val, cache)
@inferred PL.construct_fixed_optimisation_function(prob, n, val, cache)
@test new_f.f([2.31], data) ≈ negloglik([2.31, val], data)
@inferred new_f.f([2.31], data)
cache = [1.0, 2.0]
new_f = PL.construct_fixed_optimisation_function(prob, n, val, cache)
@inferred PL.construct_fixed_optimisation_function(prob, n, val, cache)
@test new_f.f([2.31], data) ≈ negloglik([2.31, val], data)
@inferred new_f.f([2.31], data)

loglik = (θ, p) -> θ[1] * p[1] + θ[2] + θ[3] + θ[4]
negloglik = PL.negate_loglik(loglik)
θ₀ = rand(4)
data = 1.301
prob = PL.construct_optimisation_problem(negloglik, θ₀, data)
val = 1.0
n = 3
cache = DiffCache(θ₀)
new_f = PL.construct_fixed_optimisation_function(prob, n, val, cache)
@inferred PL.construct_fixed_optimisation_function(prob, n, val, cache)
@test new_f.f([2.31, 4.7, 2.3], data) ≈ negloglik([2.31, 4.7, val, 2.3], data)
@inferred new_f.f([2.31, 4.7, 2.3], data)
cache = [1.0, 2.0, 3.0, 4.0]
new_f = PL.construct_fixed_optimisation_function(prob, n, val, cache)
@inferred PL.construct_fixed_optimisation_function(prob, n, val, cache)

#@benchmark $new_f.f($[2.31, 4.7, 2.3], $data)


## Test that we can correctly exclude a parameter
loglik = (θ, p) -> θ[1] * p[1] + θ[2]
negloglik = PL.negate_loglik(loglik)
θ₀ = rand(2)
data = [1.0]
prob = PL.construct_optimisation_problem(negloglik, θ₀, data)
n = 1
new_prob = PL.exclude_parameter(prob, n)
@inferred PL.exclude_parameter(prob, n)
@test !PL.has_bounds(new_prob)
@test new_prob.u0 == [θ₀[2]]

n = 2
new_prob = PL.exclude_parameter(prob, n)
@inferred PL.exclude_parameter(prob, n)
@test !PL.has_bounds(new_prob)
@test new_prob.u0 == [θ₀[1]]

prob = PL.construct_optimisation_problem(negloglik, θ₀, data; lb=[1.0, 2.0], ub=[10.0, 20.0])
n = 1
new_prob = PL.exclude_parameter(prob, n)
@inferred PL.exclude_parameter(prob, n)
@test PL.has_bounds(new_prob)
@test PL.get_lower_bounds(new_prob) == [2.0]
@test PL.get_upper_bounds(new_prob) == [20.0]
@test new_prob.u0 == [θ₀[2]]

n = 2
new_prob = PL.exclude_parameter(prob, n)
@inferred PL.exclude_parameter(prob, n)
@test PL.has_bounds(new_prob)
@test PL.get_lower_bounds(new_prob) == [1.0]
@test PL.get_upper_bounds(new_prob) == [10.0]
@test new_prob.u0 == [θ₀[1]]

## Test that we can shift the objective function 
loglik = (θ, p) -> θ[1] * p[1] + θ[2]
negloglik = PL.negate_loglik(loglik)
θ₀ = rand(2)
data = [1.0]
prob = PL.construct_optimisation_problem(negloglik, θ₀, data)
new_prob = PL.shift_objective_function(prob, 0.2291)
@inferred PL.shift_objective_function(prob, 0.2291)
@test new_prob.f(θ₀, data) ≈ negloglik(θ₀, data) - 0.2291
@inferred new_prob.f(θ₀, data)

######################################################
## LikelihoodProblem 
######################################################
## Test that we are correctly negating the likelihood 
loglik = (θ, p) -> 2.0
negloglik = ProfileLikelihood.negate_loglik(loglik)
@test negloglik(rand(), rand()) == -2.0

loglik = (θ, p) -> θ[1] * p[1] + θ[2]
negloglik = ProfileLikelihood.negate_loglik(loglik)
θ, p = rand(2), rand()
@test negloglik(θ, p) ≈ -loglik(θ, p)

## Test the construction of the OptimizationFunction 
loglik = (θ, p) -> θ[1] * p[1] + θ[2]
negloglik = ProfileLikelihood.negate_loglik(loglik)
optf_1 = ProfileLikelihood.construct_optimisation_function(negloglik, 1:5)
@test optf_1 == OptimizationFunction(negloglik, SciMLBase.NoAD(); syms=1:5)

paramsym_vec = [:a, :sys]
optf_2 = ProfileLikelihood.construct_optimisation_function(negloglik, 1:5; paramsyms=paramsym_vec)
@test optf_2 === OptimizationFunction(negloglik, SciMLBase.NoAD(); syms=1:5, paramsyms=paramsym_vec)

adtype = Optimization.AutoFiniteDiff()
optf_3 = ProfileLikelihood.construct_optimisation_function(negloglik, 1:5; adtype=adtype, paramsyms=paramsym_vec)
@test optf_3 === OptimizationFunction(negloglik, adtype; syms=1:5, paramsyms=paramsym_vec)

## Test the construction of the OptimizationProblem 
loglik = (θ, p) -> θ[1] * p[1] + θ[2]
negloglik = ProfileLikelihood.negate_loglik(loglik)
θ₀ = rand(3)
data = (rand(100), [:a, :b])
prob = ProfileLikelihood.construct_optimisation_problem(negloglik, θ₀, data)
@test prob == OptimizationProblem(negloglik, θ₀, data)
@test !PL.has_upper_bounds(prob)
@test !PL.has_lower_bounds(prob)
@test !PL.has_bounds(prob)

lb = [1.0, 2.0]
ub = [Inf, Inf]
prob = ProfileLikelihood.construct_optimisation_problem(negloglik, θ₀, data; lb=lb, ub=ub)
@test prob == OptimizationProblem(negloglik, θ₀, data; lb=lb, ub=ub)
@test prob.lb === lb == PL.get_lower_bounds(prob)
@test prob.ub === ub == PL.get_upper_bounds(prob)
@test PL.finite_lower_bounds(prob)
@test !PL.finite_upper_bounds(prob)
@test PL.has_upper_bounds(prob)
@test PL.has_lower_bounds(prob)
@test PL.has_bounds(prob)
@test PL.get_lower_bounds(prob, 1) == 1.0
@test PL.get_lower_bounds(prob, 2) == 2.0
@test PL.get_upper_bounds(prob, 1) == Inf
@test PL.get_upper_bounds(prob, 2) == Inf

## Test the construction of the integrator 
f = (u, p, t) -> 1.01u
u₀ = 0.5
tspan = (0.0, 1.0)
p = nothing
ode_alg = Tsit5()
integ = ProfileLikelihood.construct_integrator(f, u₀, tspan, p, ode_alg)
solve!(integ)
@test all([abs(integ.sol.u[i] - 0.5exp(1.01integ.sol.t[i])) < 0.01 for i in eachindex(integ.sol)])
@test integ.alg == ode_alg

ode_alg = Rosenbrock23()
integ = ProfileLikelihood.construct_integrator(f, u₀, tspan, p, ode_alg; saveat=0.25)
solve!(integ)
@test all([abs(integ.sol.u[i] - 0.5exp(1.01integ.sol.t[i])) < 0.01 for i in eachindex(integ.sol)])
@test integ.sol.t == 0:0.25:1.0

## Test the construction of the LikelihoodProblem with normal inputs
loglik = (θ, p) -> θ[1] * p[1] + θ[2]
θ₀ = [5.0, 2.0]
syms = [:a, :b]
prob = ProfileLikelihood.LikelihoodProblem(loglik, θ₀; syms)
@test PL.get_problem(prob) == prob.problem
@test PL.get_data(prob) == prob.data
@test PL.get_log_likelihood_function(prob) == loglik
@test PL.get_θ₀(prob) == θ₀ == prob.θ₀ == prob.problem.u0
@test PL.get_θ₀(prob, 1) == 5.0
@test PL.get_θ₀(prob, 2) == 2.0
@test PL.get_syms(prob) == syms == prob.syms
@test !PL.has_upper_bounds(prob)
@test !PL.has_lower_bounds(prob)
@test !PL.finite_lower_bounds(prob)
@test !PL.finite_upper_bounds(prob)
@test !PL.has_bounds(prob)
@test PL.number_of_parameters(prob) == 2

adtype = Optimization.AutoFiniteDiff()
prob = PL.LikelihoodProblem(loglik, θ₀; syms, f_kwargs=(adtype=adtype,))
@test PL.get_problem(prob) == prob.problem
@test PL.get_data(prob) == prob.data
@test PL.get_log_likelihood_function(prob) == loglik
@test PL.get_θ₀(prob) == θ₀ == prob.θ₀ == prob.problem.u0
@test PL.get_syms(prob) == syms == prob.syms
@test prob.problem.f.adtype isa Optimization.AutoFiniteDiff
@test prob.problem.lb === nothing == PL.get_lower_bounds(prob)
@test prob.problem.ub === nothing == PL.get_upper_bounds(prob)
@test !PL.has_upper_bounds(prob)
@test !PL.has_lower_bounds(prob)
@test !PL.finite_lower_bounds(prob)
@test !PL.finite_upper_bounds(prob)
@test !PL.finite_bounds(prob)
@test !PL.has_bounds(prob)
@test PL.number_of_parameters(prob) == 2

adtype = Optimization.AutoFiniteDiff()
data = [1.0, 3.0]
lb = [3.0, -3.0]
ub = [Inf, Inf]
prob = PL.LikelihoodProblem(loglik, θ₀; f_kwargs=(adtype=adtype,), prob_kwargs=(lb=lb, ub=ub), data)
@test PL.get_problem(prob) == prob.problem
@test PL.get_data(prob) == data == prob.data
@test PL.get_log_likelihood_function(prob) == loglik
@test PL.get_θ₀(prob) == θ₀ == prob.θ₀ == prob.problem.u0
@test PL.get_syms(prob) == 1:2
@test prob.problem.f.adtype isa Optimization.AutoFiniteDiff
@test prob.problem.lb == lb == PL.get_lower_bounds(prob)
@test prob.problem.ub == ub == PL.get_upper_bounds(prob)
@test PL.has_upper_bounds(prob)
@test PL.has_lower_bounds(prob)
@test PL.finite_lower_bounds(prob)
@test !PL.finite_upper_bounds(prob)
@test !PL.finite_bounds(prob)
@test PL.has_bounds(prob)
@test PL.number_of_parameters(prob) == 2

adtype = Optimization.AutoFiniteDiff()
data = [1.0, 3.0]
lb = [Inf, Inf]
ub = [3.0, -3.0]
prob = PL.LikelihoodProblem(loglik, θ₀; f_kwargs=(adtype=adtype,), prob_kwargs=(lb=lb, ub=ub), data)
@test PL.get_problem(prob) == prob.problem
@test PL.get_data(prob) == data == prob.data
@test PL.get_log_likelihood_function(prob) == loglik
@test PL.get_θ₀(prob) == θ₀ == prob.θ₀ == prob.problem.u0
@test PL.get_syms(prob) == 1:2
@test prob.problem.f.adtype isa Optimization.AutoFiniteDiff
@test prob.problem.lb == lb == PL.get_lower_bounds(prob)
@test prob.problem.ub == ub == PL.get_upper_bounds(prob)
@test PL.has_upper_bounds(prob)
@test PL.has_lower_bounds(prob)
@test !PL.finite_lower_bounds(prob)
@test PL.finite_upper_bounds(prob)
@test !PL.finite_bounds(prob)
@test PL.has_bounds(prob)
@test PL.number_of_parameters(prob) == 2

## Test the construction of the LikelihoodProblem with an integrator
f = (u, p, t) -> 1.01u
u₀ = [0.5]
tspan = (0.0, 1.0)
p = nothing
ode_alg = Tsit5()
prob = PL.LikelihoodProblem(loglik, u₀, f, u₀, tspan;
    ode_alg, ode_kwargs=(saveat=0.25,), ode_parameters=p)
@test PL.get_problem(prob) == prob.problem
@test PL.get_data(prob) == SciMLBase.NullParameters()
@test PL.get_log_likelihood_function(prob).loglik == loglik
@test PL.get_θ₀(prob) == u₀ == prob.θ₀ == prob.problem.u0
@test PL.get_syms(prob) == [1]
@test PL.get_log_likelihood_function(prob).integrator.alg == ode_alg
@test PL.get_log_likelihood_function(prob).integrator.p == p
@test PL.get_log_likelihood_function(prob).integrator.opts.saveat.valtree == 0.25:0.25:1.0
@test PL.get_log_likelihood_function(prob).integrator.f.f == f
@test prob.problem.lb === nothing == PL.get_lower_bounds(prob)
@test prob.problem.ub === nothing == PL.get_upper_bounds(prob)
@test !PL.has_upper_bounds(prob)
@test !PL.has_lower_bounds(prob)
@test !PL.finite_lower_bounds(prob)
@test !PL.finite_upper_bounds(prob)
@test !PL.finite_bounds(prob)
@test !PL.has_bounds(prob)
@test PL.number_of_parameters(prob) == 1

p = [1.0, 3.0]
ode_alg = Rosenbrock23(autodiff=false)
dat = [2.0, 3.0]
syms = [:u]
prob = PL.LikelihoodProblem(loglik, u₀, f, u₀, tspan;
    data=dat, syms=syms,
    ode_alg, ode_kwargs=(saveat=0.25,), ode_parameters=p,
    prob_kwargs=(lb=lb, ub=ub), f_kwargs=(adtype=adtype,))
@test PL.get_problem(prob) == prob.problem
@test PL.get_data(prob) == dat
@test PL.get_log_likelihood_function(prob).loglik == loglik
@test PL.get_θ₀(prob) == u₀ == prob.θ₀ == prob.problem.u0
@test PL.get_syms(prob) == syms
@test PL.get_log_likelihood_function(prob).integrator.alg == Rosenbrock23{1,false,OrdinaryDiffEq.LinearSolve.GenericLUFactorization{OrdinaryDiffEq.LinearAlgebra.RowMaximum},typeof(OrdinaryDiffEq.DEFAULT_PRECS),Val{:forward},true,nothing}(OrdinaryDiffEq.LinearSolve.GenericLUFactorization{OrdinaryDiffEq.LinearAlgebra.RowMaximum}(OrdinaryDiffEq.LinearAlgebra.RowMaximum()), OrdinaryDiffEq.DEFAULT_PRECS)
@test PL.get_log_likelihood_function(prob).integrator.p == p
@test PL.get_log_likelihood_function(prob).integrator.opts.saveat.valtree == 0.25:0.25:1.0
@test PL.get_log_likelihood_function(prob).integrator.f.f == f
@test prob.problem.f.adtype isa Optimization.AutoFiniteDiff
@test prob.problem.lb == lb == PL.get_lower_bounds(prob)
@test prob.problem.ub == ub == PL.get_upper_bounds(prob)
@test PL.has_upper_bounds(prob)
@test PL.has_lower_bounds(prob)
@test !PL.finite_lower_bounds(prob)
@test PL.finite_upper_bounds(prob)
@test !PL.finite_bounds(prob)
@test PL.has_bounds(prob)
@test PL.number_of_parameters(prob) == 1

## Test the indexing 
loglik = (θ, p) -> θ[1] * p[1] + θ[2]
θ₀ = [5.0, 2.0]
syms = [:a, :b]
prob = ProfileLikelihood.LikelihoodProblem(loglik, θ₀; syms)
@test SciMLBase.sym_to_index(:a, prob) == 1
@test SciMLBase.sym_to_index(:b, prob) == 2
@test prob[1] == 5.0
@test prob[2] == 2.0
@test prob[:a] == 5.0
@test prob[:b] == 2.0
@test prob[[1, 2]] == [5.0, 2.0]
@test prob[1:2] == [5.0, 2.0]
@test prob[[:a, :b]] == [5.0, 2.0]
@test_throws BoundsError prob[:c]

## Test that we can replace the initial estimate
new_θ = [2.0, 3.0]
new_prob = PL.update_initial_estimate(prob, new_θ)
@test new_prob.θ₀ == new_θ
@test new_prob.problem.u0 == new_θ

######################################################
## MLE
######################################################
## Basic solution 
loglik = (θ, p) -> -(p[1] - θ[1])^2 - p[2] * (θ[2] - θ[1])^2 + 3.0
θ₀ = zeros(2)
dat = [1.0, 100.0]
prob = LikelihoodProblem(loglik, θ₀; data=dat, syms=[:α, :β],
    f_kwargs=(adtype=Optimization.AutoFiniteDiff(),))
sol = mle(prob, NLopt.LN_NELDERMEAD())
@test PL.get_mle(sol) == sol.mle ≈ [1.0, 1.0]
@test PL.get_problem(sol) == sol.problem == prob
@test PL.get_optimiser(sol) == sol.optimiser == NLopt.LN_NELDERMEAD
@test PL.get_maximum(sol) == sol.maximum ≈ 3.0
@test PL.get_retcode(sol) == sol.retcode
@test PL.number_of_parameters(prob) == 2

## Check we can use multiple algorithms
loglik = (θ, p) -> -(p[1] - θ[1])^2 - p[2] * (θ[2] - θ[1])^2 + 3.0
θ₀ = zeros(2)
dat = [1.6, 100.0]
prob = LikelihoodProblem(loglik, θ₀; data=dat, syms=[:α, :β],
    f_kwargs=(adtype=Optimization.AutoFiniteDiff(),))
alg1 = NLopt.LN_NELDERMEAD
alg2 = NLopt.LN_BOBYQA
alg3 = NLopt.LD_LBFGS
alg4 = BBO_adaptive_de_rand_1_bin()
alg = (alg1, alg2, alg3, alg4, alg1)
@test_throws "The algorithm BBO_adaptive_de_rand_1_bin requires box constraints." mle(prob, alg)
@test PL.number_of_parameters(prob) == 2

dat = [1.0, 100.0]
prob = LikelihoodProblem(loglik, θ₀; data=dat, syms=[:α, :β],
    f_kwargs=(adtype=Optimization.AutoFiniteDiff(),))
sol = mle(prob, (alg1,))
@test PL.get_mle(sol) == sol.mle ≈ [1.0, 1.0]
@test PL.get_problem(sol) == sol.problem == prob
@test PL.get_optimiser(sol) == sol.optimiser == (NLopt.LN_NELDERMEAD,)
@test PL.get_maximum(sol) == sol.maximum ≈ 3.0
@test PL.get_retcode(sol) == sol.retcode
@test PL.number_of_parameters(prob) == 2

## Check that we can index correctly
syms = [:α, :β]
prob = LikelihoodProblem(loglik, θ₀; data=dat, syms=syms,
    f_kwargs=(adtype=Optimization.AutoFiniteDiff(),),
    prob_kwargs=(lb=[-5.0, -5.0], ub=[10.0, 0.5]))
sol = mle(prob, (alg1, alg2, alg3, alg1, alg4))
@test PL.get_mle(sol) == sol.mle ≈ [0.5049504933896497, 0.5]
@test PL.get_problem(sol) == sol.problem == prob
@test PL.get_optimiser(sol) == sol.optimiser == (alg1, alg2, alg3, alg1, alg4)
@test PL.get_maximum(sol) == sol.maximum ≈ 2.7524752475247523
@test PL.get_retcode(sol) == sol.retcode
@test PL.get_syms(sol) == syms
@test PL.number_of_parameters(prob) == 2
@test PL.get_mle(sol, 1) == sol.mle[1] ≈ 0.5049504933896497
@test PL.get_mle(sol, 2) == sol.mle[2] ≈ 0.5
@test sol[1] == sol.mle[1]
@test sol[2] == sol.mle[2]
@test SciMLBase.sym_to_index(:α, sol) == 1
@test SciMLBase.sym_to_index(:β, sol) == 2
@test sol[:α] == sol.mle[1]
@test sol[:β] == sol.mle[2]
@test sol[[:α, :β]] == sol.mle
@test sol[[:β, :α]] == [sol.mle[2], sol.mle[1]]
@test sol[1:2] == sol.mle[1:2]
@test sol[[1, 2]] == sol.mle[[1, 2]]

## Check that we can use a sol to update an initial estimate 
syms = [:α, :β]
prob = LikelihoodProblem(loglik, θ₀; data=dat, syms=syms,
    f_kwargs=(adtype=Optimization.AutoFiniteDiff(),),
    prob_kwargs=(lb=[-5.0, -5.0], ub=[10.0, 0.5]))
sol = mle(prob, (alg1, alg2, alg3, alg1, alg4))
new_prob = PL.update_initial_estimate(prob, sol)
@test new_prob.θ₀ == new_prob.problem.u0 == sol.mle
@test PL.update_initial_estimate(new_prob, sol) == new_prob

######################################################
## RegularGrid 
######################################################
## Check that the stepsizes are being computed correctly 
lb = [2.0, 3.0, 5.0]
ub = [5.0, 5.3, 13.2]
res = 50
@test all(i -> PL.compute_step_size(lb, ub, res, i) == (ub[i] - lb[i]) / (res - 1), eachindex(lb))

lb = [2.7, 13.3, 45.4, 10.0]
ub = [-1.0, -1.0, 5.0, 9.9]
res = [4, 18, 49, 23]
@test all(i -> PL.compute_step_size(lb, ub, res, i) == (ub[i] - lb[i]) / (res[i] - 1), eachindex(lb))

@test PL.compute_step_size(2.0, 5.7, 43) == 3.7 / 42

## Test that the grid is constructed correctly 
lb = [2.7, 5.3, 10.0]
ub = [10.0, 7.7, 14.4]
res = 50
ug = PL.RegularGrid(lb, ub, res)
@test PL.get_lower_bounds(ug) == ug.lower_bounds == lb
@test PL.get_upper_bounds(ug) == ug.upper_bounds == ub
@test all(i -> PL.get_lower_bounds(ug, i) == lb[i], eachindex(lb))
@test all(i -> PL.get_upper_bounds(ug, i) == ub[i], eachindex(ub))
@test PL.get_step_sizes(ug) == ug.step_sizes
@test all(i -> PL.get_step_sizes(ug, i) == (ub[i] - lb[i]) / (res - 1) == ug.step_sizes[i], eachindex(lb))
@test PL.get_resolutions(ug) == ug.resolution
@test all(i -> PL.get_resolutions(ug, i) == res == ug.resolution, eachindex(lb))
@test PL.number_of_parameters(ug) == 3
for i in eachindex(lb)
    for j in 1:res
        @test PL.get_step(ug, i, j) ≈ (j - 1) * (ub[i] - lb[i]) / (res - 1)
        @test PL.increment_parameter(ug, i, j) == ug[i, j] ≈ lb[i] + (j - 1) * (ub[i] - lb[i]) / (res - 1)
    end
end
@test PL.number_type(ug) == Float64

lb = [2.7, 5.3, 10.0, 4.4]
ub = [10.0, 7.7, 14.4, -57.4]
res = [50, 32, 10, 100]
ug = PL.RegularGrid(lb, ub, res)
@test PL.get_lower_bounds(ug) == ug.lower_bounds == lb
@test PL.get_upper_bounds(ug) == ug.upper_bounds == ub
@test all(i -> PL.get_lower_bounds(ug, i) == lb[i], eachindex(lb))
@test all(i -> PL.get_upper_bounds(ug, i) == ub[i], eachindex(ub))
@test PL.get_step_sizes(ug) == ug.step_sizes
@test all(i -> PL.get_step_sizes(ug, i) == (ub[i] - lb[i]) / (res[i] - 1) == ug.step_sizes[i], eachindex(lb))
@test PL.get_resolutions(ug) == ug.resolution
@test all(i -> PL.get_resolutions(ug, i) == res[i] == ug.resolution[i], eachindex(res))
@test PL.number_of_parameters(ug) == 4
for i in eachindex(lb)
    for j in 1:res[i]
        @test PL.get_step(ug, i, j) ≈ (j - 1) * (ub[i] - lb[i]) / (res[i] - 1)
        @test PL.increment_parameter(ug, i, j) == ug[i, j] ≈ lb[i] + (j - 1) * (ub[i] - lb[i]) / (res[i] - 1)
    end
end
@test PL.number_type(ug) == Float64

## Test that we can get the parameters correctly 
lb = [2.7, 5.3, 10.0, 4.4]
ub = [10.0, 7.7, 14.4, -57.4]
res = [50, 32, 10, 100]
ug = PL.RegularGrid(lb, ub, res)
I = (2, 3, 4, 10)
θ = PL.get_parameters(ug, I)
@test θ == [ug[1, 2], ug[2, 3], ug[3, 4], ug[4, 10]]

I = (27, 31, 9, 100)
θ = PL.get_parameters(ug, I)
@test θ == [ug[1, 27], ug[2, 31], ug[3, 9], ug[4, 100]]

######################################################
## IrregularGrid
######################################################
## Test that we are constructing it correctly 
lb = [2.0, 5.0, 1.3]
ub = [5.0, 10.0, 17.3]
grid = [rand(2) for _ in 1:200]
ig = PL.IrregularGrid(lb, ub, grid)
@test PL.get_lower_bounds(ig) == ig.lower_bounds == lb
@test PL.get_upper_bounds(ig) == ig.upper_bounds == ub
@test all(i -> PL.get_lower_bounds(ig, i) == lb[i], eachindex(lb))
@test all(i -> PL.get_upper_bounds(ig, i) == ub[i], eachindex(ub))
@test PL.get_grid(ig) == grid
@test all(i -> PL.get_parameters(grid, i) == ig[i] == grid[i], eachindex(grid))
@test PL.number_type(ig) == Float64
@test PL.number_of_parameter_sets(ig) == 200
@test PL.each_parameter(ig) == 1:200

lb = [2.0, 5.0, 1.3]
ub = [5.0, 10.0, 17.3]
grid = rand(3, 50)
ig = PL.IrregularGrid(lb, ub, grid)
@test PL.get_lower_bounds(ig) == ig.lower_bounds == lb
@test PL.get_upper_bounds(ig) == ig.upper_bounds == ub
@test all(i -> PL.get_lower_bounds(ig, i) == lb[i], eachindex(lb))
@test all(i -> PL.get_upper_bounds(ig, i) == ub[i], eachindex(ub))
@test PL.get_grid(ig) == grid
@test all(i -> PL.get_parameters(grid, i) == ig[i] == grid[:, i], axes(grid, 2))
@test PL.number_type(ig) == Float64
@test PL.number_of_parameter_sets(ig) == 50
@test PL.each_parameter(ig) == 1:50

######################################################
## GridSearch
######################################################
## Test that we are constructing the grid correctly 
f = (x, _) -> x[1] * x[2] * x[3]
lb = [2.7, 5.3, 10.0]
ub = [10.0, 7.7, 14.4]
res = 50
ug = PL.RegularGrid(lb, ub, res)
gs = PL.GridSearch(f, ug)
@test gs.f isa FunctionWrappers.FunctionWrapper{Float64,Tuple{Vector{Float64},Nothing}}
@test gs.f.obj[] == f
@test PL.get_grid(gs) == gs.grid == ug
@test PL.get_function(gs) == gs.f
@test PL.eval_function(gs, [1.0, 2.0, 3.0]) ≈ 6.0
@inferred PL.eval_function(gs, rand(3))
@test PL.number_of_parameters(gs) == 3
@test PL.get_parameters(gs) === nothing

f = (x, _) -> x[1] * x[2] * x[3] + x[4]
lb = [2.0, 5.0, 1.3, 5.0]
ub = [5.0, 10.0, 17.3, 20.0]
grid = [rand(2) for _ in 1:200]
ig = PL.IrregularGrid(lb, ub, grid)
gs = PL.GridSearch(f, ig, 2.0)
@test gs.f isa FunctionWrappers.FunctionWrapper{Float64,Tuple{Vector{Float64},Float64}}
@test gs.f.obj[] == f
@test PL.get_grid(gs) == gs.grid == ig
@test PL.get_function(gs) == gs.f
@test PL.eval_function(gs, [1.0, 4.2, 4.2, -1.0]) ≈ f([1.0, 4.2, 4.2, -1.0], 2.0)
@inferred PL.eval_function(gs, rand(4))
@test PL.number_of_parameters(gs) == 4
@test PL.get_parameters(gs) == 2.0

## Test that we are preparing the grid correctly 
lb = [2.0, 5.0, 1.3, 5.0]
ub = [5.0, 10.0, 17.3, 20.0]
grid = [rand(2) for _ in 1:200]
ig = PL.IrregularGrid(lb, ub, grid)
A_ig = PL.prepare_grid(ig)
@test A_ig == zeros(200)

lb = [2.7, 5.3, 10.0]
ub = [10.0, 7.7, 14.4]
res = 50
ug = PL.RegularGrid(lb, ub, res)
A_ug = PL.prepare_grid(ug)
@test A_ug == zeros(50, 50, 50)

lb = [2.7, 5.3, 10.0]
ub = [10.0, 7.7, 14.4]
res = [20, 50, 70]
ug_2 = PL.RegularGrid(lb, ub, res)
A_ug_2 = PL.prepare_grid(ug_2)
@test A_ug_2 == zeros(20, 50, 70)

gs1 = PL.GridSearch(f, ig)
gs2 = PL.GridSearch(f, ug)
gs3 = PL.GridSearch(f, ug_2)
B_ig = PL.prepare_grid(gs1)
B_ug = PL.prepare_grid(gs2)
B_ug_2 = PL.prepare_grid(gs3)
@test B_ig == A_ig
@test B_ug == A_ug
@test B_ug_2 == A_ug_2

## Test that we are getting the correct likelihood function from GridSearch 
loglik = (θ, p) -> -(p[1] - θ[1])^2 - p[2] * (θ[2] - θ[1])^2 + 3.0
θ₀ = zeros(2)
dat = [1.6, 100.0]
prob = LikelihoodProblem(loglik, θ₀; data=dat, syms=[:α, :β],
    f_kwargs=(adtype=Optimization.AutoFiniteDiff(),))
lb = [2.7, 5.3, 10.0]
ub = [10.0, 7.7, 14.4]
res = [20, 50, 70]
ug = RegularGrid(lb, ub, res)
gs = GridSearch(prob, ug)
@test PL.eval_function(gs, [1.0, 2.7]) == loglik([1.0, 2.7], dat)
@inferred PL.eval_function(gs, [1.0, 2.7])
@test PL.get_grid(gs) == ug

lb = [2.0, 5.0, 1.3, 5.0]
ub = [5.0, 10.0, 17.3, 20.0]
grid = [rand(2) for _ in 1:200]
ig = IrregularGrid(lb, ub, grid)
gs = GridSearch(prob, ig)
@test PL.eval_function(gs, [1.0, 2.7]) == loglik([1.0, 2.7], dat)
@inferred PL.eval_function(gs, [1.0, 2.7])
@test PL.get_grid(gs) == ig

## Test that the GridSearch works on a set of problems
# Rastrigin function 
n = 4
A = 10
rastrigin_f(x, _) = @inline @inbounds A * n + (x[1]^2 - A * cos(2π * x[1])) + (x[2]^2 - A * cos(2π * x[2])) + (x[3]^2 - A * cos(2π * x[3])) + (x[4]^2 - A * cos(2π * x[4]))
@test rastrigin_f(zeros(n), nothing) == 0.0
ug = PL.RegularGrid(repeat([-5.12], n), repeat([5.12], n), 25)
gs = PL.GridSearch((x, _) -> (@inline; -rastrigin_f(x, nothing)), ug)
f_min, x_min = PL.grid_search(gs)
@inferred PL.grid_search(gs)
@inferred PL.grid_search(gs; save_vals=Val(true))
@inferred PL.grid_search(gs; save_vals=Val(false), parallel=Val(true))
@inferred PL.grid_search(gs; save_vals=Val(true), parallel=Val(true))
@inferred PL.grid_search(gs; save_vals=Val(true), minimise=Val(true))
@inferred PL.grid_search(gs; save_vals=Val(false), parallel=Val(true), minimise=Val(true))
@inferred PL.grid_search(gs; save_vals=Val(true), parallel=Val(true), minimise=Val(true))
@inferred PL.grid_search(gs; minimise=Val(true))

@test f_min ≈ 0.0
@test x_min ≈ zeros(n)

gs = PL.GridSearch(rastrigin_f, ug)
f_min, x_min = grid_search(gs; minimise=Val(true))
@test f_min ≈ 0.0
@test x_min ≈ zeros(n)
@inferred PL.grid_search(gs; minimise=Val(true))

f_min, x_min, f_res = grid_search(gs; minimise=Val(true), save_vals=Val(true))
@test f_min ≈ 0.0
@test x_min ≈ zeros(n)

param_ranges = [LinRange(-5.12, 5.12, 25) for i in 1:n]
@test f_res ≈ [rastrigin_f(x, nothing) for x in Iterators.product(param_ranges...)]

for _ in 1:250
    lb = repeat([-5.12], n)
    ub = repeat([5.12], n)
    gr = rand(n, 2000)
    ig = PL.IrregularGrid(lb, ub, gr)
    f_min, x_min = grid_search(rastrigin_f, ig; minimise=Val(true))
    @inferred grid_search(rastrigin_f, ig; minimise=Val(true))
    @test f_min == minimum(rastrigin_f(x, nothing) for x in eachcol(gr))
    xm = findmin(x -> rastrigin_f(x, nothing), eachcol(gr))[2]
    @test x_min == gr[:, xm]

    gr = [rand(n) for _ in 1:2000]
    ig = PL.IrregularGrid(lb, ub, gr)
    f_min, x_min = grid_search(rastrigin_f, ig; minimise=Val(false))
    @test f_min == maximum(rastrigin_f(x, nothing) for x in gr)
    xm = findmax(x -> rastrigin_f(x, nothing), gr)[2]
    @test x_min == gr[xm]
end

# Ackley function 
n = 2
ackley_f(x, _) = -20exp(-0.2sqrt(x[1]^2 + x[2]^2)) - exp(0.5(cos(2π * x[1]) + cos(2π * x[2]))) + exp(1) + 20
@test ackley_f([0, 0], nothing) == 0
lb = repeat([-15.12], n)
ub = repeat([15.12], n)
res = (73, 121)
ug = RegularGrid(lb, ub, res)
f_min, x_min = grid_search(ackley_f, ug; minimise=Val(true))
@test f_min ≈ 0.0 atol = 1e-7
@test x_min ≈ zeros(n) atol = 1e-7

f_min, x_min = grid_search((x, _) -> -ackley_f(x, nothing), ug; minimise=Val(false))
@test f_min ≈ 0.0 atol = 1e-7
@test x_min ≈ zeros(n) atol = 1e-7

f_min, x_min, f_res = grid_search(ackley_f, ug; minimise=Val(true), save_vals=Val(true))
param_ranges = [LinRange(lb[i], ub[i], res[i]) for i in 1:n]
@test f_res ≈ [ackley_f(x, nothing) for x in Iterators.product(param_ranges...)]

f_min, x_min, f_res = grid_search((x, _) -> -ackley_f(x, nothing), ug; minimise=Val(false), save_vals=Val(true))
@test f_res ≈ [-ackley_f(x, nothing) for x in Iterators.product(param_ranges...)]

for _ in 1:250
    gr = rand(n, 500)
    ig = IrregularGrid(lb, ub, gr)
    f_min, x_min = grid_search(ackley_f, ig; minimise=Val(true))
    @inferred grid_search(ackley_f, ig; minimise=Val(true))
    @test f_min == minimum(ackley_f(x, nothing) for x in eachcol(gr))
    xm = findmin(x -> ackley_f(x, nothing), eachcol(gr))[2]
    @test x_min == gr[:, xm]

    gr = [rand(n) for _ in 1:2000]
    ig = IrregularGrid(lb, ub, gr)
    f_min, x_min = grid_search(ackley_f, ig; minimise=Val(false))
    @inferred grid_search(ackley_f, ig; minimise=Val(true))
    @test f_min == maximum(ackley_f(x, nothing) for x in gr)
    xm = findmax(x -> ackley_f(x, nothing), gr)[2]
    @test x_min == gr[xm]

    gr = rand(n, 500)
    ig = IrregularGrid(lb, ub, gr)
    f_min, x_min = grid_search(ackley_f, ig; minimise=Val(true), parallel=Val(true))
    @inferred grid_search(ackley_f, ig; minimise=Val(true), parallel=Val(true))
    @test f_min == minimum(ackley_f(x, nothing) for x in eachcol(gr))
    xm = findmin(x -> ackley_f(x, nothing), eachcol(gr))[2]
    @test x_min == gr[:, xm]

    gr = [rand(n) for _ in 1:2000]
    ig = IrregularGrid(lb, ub, gr)
    f_min, x_min = grid_search(ackley_f, ig; minimise=Val(false), parallel=Val(true))
    @inferred grid_search(ackley_f, ig; minimise=Val(true), parallel=Val(true))
    @test f_min == maximum(ackley_f(x, nothing) for x in gr)
    xm = findmax(x -> ackley_f(x, nothing), gr)[2]
    @test x_min == gr[xm]
end

# Sphere function 
n = 5
sphere_f(x, _) = x[1]^2 + x[2]^2 + x[3]^2 + x[4]^2 + x[5]^2
@test sphere_f(zeros(n), nothing) == 0
lb = repeat([-15.12], n)
ub = repeat([15.12], n)
res = (15, 17, 15, 19, 23)
ug = RegularGrid(lb, ub, res)
f_min, x_min = grid_search(sphere_f, ug; minimise=Val(true))
@test f_min ≈ 0.0 atol = 1e-7
@test x_min ≈ zeros(n) atol = 1e-7

f_min, x_min = grid_search((x, _) -> -sphere_f(x, nothing), ug; minimise=Val(false))
@test f_min ≈ 0.0 atol = 1e-7
@test x_min ≈ zeros(n) atol = 1e-7

f_min, x_min, f_res = grid_search(sphere_f, ug; minimise=Val(true), save_vals=Val(true))
param_ranges = [LinRange(lb[i], ub[i], res[i]) for i in 1:n]
@test f_res ≈ [sphere_f(x, nothing) for x in Iterators.product(param_ranges...)]
f_min, x_min, f_res = grid_search((x, _) -> -sphere_f(x, nothing), ug; minimise=Val(false), save_vals=Val(true))
@test f_res ≈ [-sphere_f(x, nothing) for x in Iterators.product(param_ranges...)]

f_min, x_min, f_res = grid_search(sphere_f, ug; minimise=Val(true), save_vals=Val(true), parallel=Val(true))
param_ranges = [LinRange(lb[i], ub[i], res[i]) for i in 1:n]
@test f_res ≈ [sphere_f(x, nothing) for x in Iterators.product(param_ranges...)]
f_min, x_min, f_res = grid_search((x, _) -> -sphere_f(x, nothing), ug; minimise=Val(false), save_vals=Val(true), parallel=Val(true))
@test f_res ≈ [-sphere_f(x, nothing) for x in Iterators.product(param_ranges...)]

for _ in 1:250
    gr = rand(n, 500)
    ig = IrregularGrid(lb, ub, gr)
    f_min, x_min = grid_search(sphere_f, ig; minimise=Val(true))
    @inferred grid_search(sphere_f, ig; minimise=Val(true))
    @test f_min == minimum(sphere_f(x, nothing) for x in eachcol(gr))
    xm = findmin(x -> sphere_f(x, nothing), eachcol(gr))[2]
    @test x_min == gr[:, xm]

    gr = rand(n, 500)
    ig = IrregularGrid(lb, ub, gr)
    f_min, x_min, f_res = grid_search(sphere_f, ig; minimise=Val(true), save_vals=Val(true))
    @inferred grid_search(sphere_f, ig; minimise=Val(true), save_vals=Val(true))
    @test f_min == minimum(sphere_f(x, nothing) for x in eachcol(gr))
    xm = findmin(x -> sphere_f(x, nothing), eachcol(gr))[2]
    @test x_min == gr[:, xm]
    @test f_res ≈ [(sphere_f(x, nothing) for x in eachcol(gr))...]

    gr = [rand(n) for _ in 1:2000]
    ig = IrregularGrid(lb, ub, gr)
    f_min, x_min = grid_search(sphere_f, ig; minimise=Val(false))
    @test f_min == maximum(sphere_f(x, nothing) for x in gr)
    xm = findmax(x -> sphere_f(x, nothing), gr)[2]
    @test x_min == gr[xm]

    gr = [rand(n) for _ in 1:2000]
    ig = IrregularGrid(lb, ub, gr)
    f_min, x_min, f_res = grid_search(sphere_f, ig; minimise=Val(false), save_vals=Val(true))
    @test f_min == maximum(sphere_f(x, nothing) for x in gr)
    xm = findmax(x -> sphere_f(x, nothing), gr)[2]
    @test x_min == gr[xm]
    @test f_res ≈ [(sphere_f(x, nothing) for x in gr)...]
end

# Multiple Linear Regression
prob, loglikk, θ, dat = multiple_linear_regression()
true_ℓ = loglikk(reduce(vcat, θ), dat)
lb = (1e-12, -3.0, 0.0, 0.0, -6.0)
ub = (0.2, 0.0, 3.0, 3.0, 6.0)
res = 27
ug = RegularGrid(lb, ub, res)
sol = grid_search(prob, ug; save_vals=Val(false))
@inferred grid_search(prob, ug; save_vals=Val(false))
@test sol isa PL.LikelihoodSolution
@test PL.get_maximum(sol) ≈ 281.7360323629172
@test PL.get_mle(sol) ≈ [0.09230769230823077
    -0.9230769230769231
    0.8076923076923077
    0.46153846153846156
    3.2307692307692317]
param_ranges = [LinRange(lb[i], ub[i], res) for i in eachindex(lb)]
f_res_true = [loglikk(collect(x), dat) for x in Iterators.product(param_ranges...)]
@test PL.get_maximum(sol) ≈ maximum(f_res_true)
max_idx = Tuple(findmax(f_res_true)[2])
@test PL.get_mle(sol) ≈ [ug[i, max_idx[i]] for i in eachindex(lb)]

sol, f_res = grid_search(prob, ug; save_vals=Val(true))
@inferred grid_search(prob, ug; save_vals=Val(true))
@test f_res ≈ f_res_true
@test PL.get_maximum(sol) ≈ 281.7360323629172
@test PL.get_mle(sol) ≈ [0.09230769230823077
    -0.9230769230769231
    0.8076923076923077
    0.46153846153846156
    3.2307692307692317]

Random.seed!(82882828)
gr = Matrix(reduce(hcat, [lb[i] .+ (ub[i] - lb[i]) .* rand(250) for i in eachindex(lb)])')
gr = hcat(gr, [0.09230769230823077, -0.9230769230769231, 0.8076923076923077, 0.46153846153846156, 3.2307692307692317])
ig = IrregularGrid(lb, ub, gr)
sol = grid_search(prob, ig; save_vals=Val(false))
@inferred grid_search(prob, ig; save_vals=Val(false))
@test sol isa PL.LikelihoodSolution
@test PL.get_maximum(sol) ≈ 281.7360323629172
@test PL.get_mle(sol) ≈ [0.09230769230823077
    -0.9230769230769231
    0.8076923076923077
    0.46153846153846156
    3.2307692307692317]
f_res_true = [loglikk(x, dat) for x in eachcol(gr)]
@test PL.get_maximum(sol) ≈ maximum(f_res_true)
max_idx = findmax(f_res_true)[2]
@test PL.get_mle(sol) ≈ gr[:, max_idx] == PL.get_parameters(ig, max_idx)

sol, f_res = grid_search(prob, ig; save_vals=Val(true))
@inferred grid_search(prob, ig; save_vals=Val(true))
@test f_res ≈ f_res_true
@test PL.get_maximum(sol) ≈ 281.7360323629172
@test PL.get_mle(sol) ≈ [0.09230769230823077
    -0.9230769230769231
    0.8076923076923077
    0.46153846153846156
    3.2307692307692317]

Random.seed!(82882828)
gr = Matrix(reduce(hcat, [lb[i] .+ (ub[i] - lb[i]) .* rand(250) for i in eachindex(lb)])')
gr = hcat(gr, [0.09230769230823077, -0.9230769230769231, 0.8076923076923077, 0.46153846153846156, 3.2307692307692317])
gr = [collect(x) for x in eachcol(gr)]
ig = IrregularGrid(lb, ub, gr)
sol = grid_search(prob, ig; save_vals=Val(false))
@inferred grid_search(prob, ig; save_vals=Val(false))
@test sol isa PL.LikelihoodSolution
@test PL.get_maximum(sol) ≈ 281.7360323629172
@test PL.get_mle(sol) ≈ [0.09230769230823077
    -0.9230769230769231
    0.8076923076923077
    0.46153846153846156
    3.2307692307692317]
f_res_true = [loglikk(x, dat) for x in gr]
@test PL.get_maximum(sol) ≈ maximum(f_res_true)
max_idx = findmax(f_res_true)[2]
@test PL.get_mle(sol) ≈ gr[max_idx] == PL.get_parameters(ig, max_idx)

sol, f_res = grid_search(prob, ig; save_vals=Val(true))
@inferred grid_search(prob, ig; save_vals=Val(true))
@test f_res ≈ f_res_true
@test PL.get_maximum(sol) ≈ 281.7360323629172
@test PL.get_mle(sol) ≈ [0.09230769230823077
    -0.9230769230769231
    0.8076923076923077
    0.46153846153846156
    3.2307692307692317]

## Test that the parallel grid searches are working 
# Rastrigin
n = 4
A = 10
rastrigin_f(x, _) = @inline @inbounds 10 * 4 + (x[1]^2 - 10 * cos(2π * x[1])) + (x[2]^2 - 10 * cos(2π * x[2])) + (x[3]^2 - 10 * cos(2π * x[3])) + (x[4]^2 - 10 * cos(2π * x[4]))
@test rastrigin_f(zeros(n), nothing) == 0.0
ug = RegularGrid(repeat([-5.12], n), repeat([5.12], n), 45)
gs = GridSearch(rastrigin_f, ug)
f_op_par, x_ar_par, f_res_par = grid_search(gs; minimise=Val(true), save_vals=Val(true), parallel=Val(true))
f_op_ser, x_ar_ser, f_res_ser = grid_search(gs; minimise=Val(true), save_vals=Val(true))
@test f_res_ser == f_res_par
@test f_op_par == f_op_ser
@test x_ar_par == x_ar_ser

# Multiple Linear Regression
prob, loglikk, θ, dat = multiple_linear_regression()
true_ℓ = loglikk(reduce(vcat, θ), dat)
lb = (1e-12, -3.0, 0.0, 0.0, -6.0)
ub = (0.2, 0.0, 3.0, 3.0, 6.0)
res = 27
ug = RegularGrid(lb, ub, res)
sol, L1 = grid_search(prob, ug; save_vals=Val(true))
sol2, L2 = grid_search(prob, ug; save_vals=Val(true), parallel=Val(true))
@test L1 ≈ L2
@test PL.get_mle(sol) ≈ PL.get_mle(sol2)

f = prob.log_likelihood_function
p = prob.data
gs = GridSearch(f, ug, p)
_opt, _sol, _L1 = grid_search(gs; save_vals=Val(true), minimise=Val(false))
_opt2, _sol2, _L2 = grid_search(gs; save_vals=Val(true), parallel=Val(true), minimise=Val(false))
@test L1 == _L1
@test _opt ≈ sol.maximum
@test _sol ≈ sol.mle
@test L2 ≈ _L2
@test _opt2 ≈ sol2.maximum
@test _sol2 ≈ sol2.mle
@test _L1 ≈ _L2

res = 27
gr = [lb[i] .+ (ub[i] - lb[i]) * rand(20) for i in eachindex(lb)]
gr = Matrix(reduce(hcat, gr)')
ug = IrregularGrid(lb, ub, gr)
sol, L1 = grid_search(prob, ug; save_vals=Val(true))
sol2, L2 = grid_search(prob, ug; save_vals=Val(true), parallel=Val(true))
@test L1 ≈ L2
@test PL.get_mle(sol) ≈ PL.get_mle(sol2)

f = prob.log_likelihood_function
p = prob.data
gs = GridSearch(f, ug, p)
_opt, _sol, _L1 = grid_search(gs; save_vals=Val(true), minimise=Val(false))
_opt2, _sol2, _L2 = grid_search(gs; save_vals=Val(true), parallel=Val(true), minimise=Val(false))
@test L1 == _L1
@test _opt ≈ sol.maximum
@test _sol ≈ sol.mle
@test L2 ≈ _L2
@test _opt2 ≈ sol2.maximum
@test _sol2 ≈ sol2.mle
@test _L1 ≈ _L2

# Logistic 
Random.seed!(2929911002)
u₀, λ, K, n, T = 0.5, 1.0, 1.0, 100, 10.0
t = LinRange(0, T, n)
u = @. K * u₀ * exp(λ * t) / (K - u₀ + u₀ * exp(λ * t))
σ = 0.1
uᵒ = u .+ [0.0, σ * randn(length(u) - 1)...] # add some noise 
@inline function ode_fnc(u, p, t)
    local λ, K
    λ, K = p
    du = λ * u * (1 - u / K)
    return du
end
@inline function loglik_fnc2(θ::AbstractVector{T}, data, integrator) where {T}
    local uᵒ, n, λ, K, σ, u0
    uᵒ, n = data
    λ, K, σ, u0 = θ
    integrator.p[1] = λ
    integrator.p[2] = K
    reinit!(integrator, u0)
    solve!(integrator)
    if !SciMLBase.successful_retcode(integrator.sol)
        return typemin(T)
    end
    return gaussian_loglikelihood(uᵒ, integrator.sol.u, σ, n)
end
θ₀ = [0.7, 2.0, 0.15, 0.4]
lb = [0.0, 1e-6, 1e-6, 0.0]
ub = [10.0, 10.0, 10.0, 10.0]
syms = [:λ, :K, :σ, :u₀]
prob = LikelihoodProblem(
    loglik_fnc2, θ₀, ode_fnc, u₀, (0.0, T); # u₀ is just a placeholder IC in this case
    syms=syms,
    data=(uᵒ, n),
    ode_parameters=[1.0, 1.0], # temp values for [λ, K],
    ode_kwargs=(verbose=false, saveat=t),
    f_kwargs=(adtype=Optimization.AutoFiniteDiff(),),
    prob_kwargs=(lb=lb, ub=ub),
    ode_alg=Tsit5()
)
ug = RegularGrid(get_lower_bounds(prob), get_upper_bounds(prob), [36, 36, 36, 36])
sol, L1 = grid_search(prob, ug; save_vals=Val(true))
sol2, L2 = grid_search(prob, ug; save_vals=Val(true), parallel=Val(true))
@test L1 ≈ L2
@test PL.get_mle(sol) ≈ PL.get_mle(sol2)

#b1 = @benchmark grid_search($prob, $ug; save_vals=$Val(false))
#b2 = @benchmark grid_search($prob, $ug; save_vals=$Val(false), parallel=$Val(true))

@inferred grid_search(prob, ug; save_vals=Val(true))
@inferred grid_search(prob, ug; save_vals=Val(true), parallel=Val(true))

prob_copies = [deepcopy(prob) for _ in 1:Base.Threads.nthreads()]
gs = [GridSearch(prob_copies[i].log_likelihood_function, ug, prob_copies[i].data) for i in 1:Base.Threads.nthreads()]
_opt, _sol, _L1 = grid_search(gs[1]; save_vals=Val(true), minimise=Val(false))
_opt2, _sol2, _L2 = grid_search(gs; save_vals=Val(true), parallel=Val(true), minimise=Val(false))
@test L1 == _L1
@test _opt ≈ sol.maximum
@test _sol ≈ sol.mle
@test L2 ≈ _L2
@test _opt2 ≈ sol2.maximum
@test _sol2 ≈ sol2.mle
@test _L1 ≈ _L2

res = 27
gr = [lb[i] .+ (ub[i] - lb[i]) * rand(20) for i in eachindex(lb)]
gr = Matrix(reduce(hcat, gr)')
ug = IrregularGrid(lb, ub, gr)
sol, L1 = grid_search(prob, ug; save_vals=Val(true))
sol2, L2 = grid_search(prob, ug; save_vals=Val(true), parallel=Val(true))
@test L1 ≈ L2
@test PL.get_mle(sol) ≈ PL.get_mle(sol2)

prob_copies = [deepcopy(prob) for _ in 1:Base.Threads.nthreads()]
gs = [GridSearch(prob_copies[i].log_likelihood_function, ug, prob_copies[i].data) for i in 1:Base.Threads.nthreads()]
_opt, _sol, _L1 = grid_search(gs[1]; save_vals=Val(true), minimise=Val(false))
_opt2, _sol2, _L2 = grid_search(gs; save_vals=Val(true), parallel=Val(true), minimise=Val(false))
@test L1 == _L1
@test _opt ≈ sol.maximum
@test _sol ≈ sol.mle
@test L2 ≈ _L2
@test _opt2 ≈ sol2.maximum
@test _sol2 ≈ sol2.mle
@test _L1 ≈ _L2

######################################################
## ConfidenceInterval 
######################################################
CI = PL.ConfidenceInterval(0.1, 0.2, 0.95)
@test PL.get_lower(CI) == CI.lower == 0.1
@test PL.get_upper(CI) == CI.upper == 0.2
@test PL.get_level(CI) == CI.level == 0.95
@test PL.get_bounds(CI) == (CI.lower, CI.upper) == (0.1, 0.2)
@test CI[1] == CI.lower == 0.1
@test CI[2] == CI.upper == 0.2
@test CI[begin] == CI[1] == 0.1
@test CI[end] == CI[2] == 0.2
@test length(CI) == 0.1
a, b = CI
@test a == PL.get_lower(CI)
@test b == PL.get_upper(CI)
@test_throws BoundsError a, b, c = CI
@test 0.17 ∈ CI
@test 0.24 ∉ CI
@test 0.0 ∉ CI

######################################################
## ProfileLikelihood 
######################################################
## Test that we can correctly construct the parameter ranges
lb = -2.0
ub = 2.0
mpt = 0.0
res = 50
lr, ur = PL.construct_profile_ranges(lb, ub, mpt, res)
@test lr == LinRange(0.0, -2.0, 50)
@test ur == LinRange(0.0, 2.0, 50)

## Test that we can construct the parameter ranges from a solution 
prob, loglikk, θ, dat = multiple_linear_regression()
true_ℓ = loglikk(reduce(vcat, θ), dat)
lb = (1e-12, -3.0, 0.0, 0.0, -6.0)
ub = (0.2, 0.0, 3.0, 3.0, 6.0)
res = 27
ug = RegularGrid(lb, ub, res)
sol = grid_search(prob, ug; save_vals=Val(false))

res2 = 50
ranges = PL.construct_profile_ranges(sol, lb, ub, res2)
@test all(i -> ranges[i] == (LinRange(sol.mle[i], lb[i], res2), LinRange(sol.mle[i], ub[i], res2)), eachindex(lb))

res2 = (50, 102, 50, 671, 123)
ranges = PL.construct_profile_ranges(sol, lb, ub, res2)
@test all(i -> ranges[i] == (LinRange(sol.mle[i], lb[i], res2[i]), LinRange(sol.mle[i], ub[i], res2[i])), eachindex(lb))

## Test that we can extract a problem and solution 
prob, loglikk, θ, dat = multiple_linear_regression()
true_ℓ = loglikk(reduce(vcat, θ), dat)
lb = (1e-12, -3.0, 0.0, 0.0, -6.0)
ub = (0.2, 0.0, 3.0, 3.0, 6.0)
res = 27
ug = RegularGrid(lb, ub, res)
sol = grid_search(prob, ug; save_vals=Val(false))
_opt_prob, _mles, _ℓmax = PL.extract_problem_and_solution(prob, sol)
@test _opt_prob === sol.problem.problem
@test _mles == sol.mle
@test !(_mles === sol.mle)
@test _ℓmax == sol.maximum

## Test that we can prepare the profile results correctly 
N = 5
T = Float64
F = Float64
_θ, _prof, _other_mles, _splines, _confidence_intervals = PL.prepare_profile_results(N, T, F)
@test _θ == Dict{Int64,Vector{T}}([])
@test _prof == Dict{Int64,Vector{T}}([])
@test _other_mles == Dict{Int64,Vector{Vector{T}}}([])
@test _confidence_intervals == Dict{Int64,PL.ConfidenceInterval{T,F}}([])

## Test that we can correctly normalise the objective function 
shifted_opt_prob = PL.normalise_objective_function(_opt_prob, _ℓmax, false)
@test shifted_opt_prob === _opt_prob
shifted_opt_prob = PL.normalise_objective_function(_opt_prob, _ℓmax, true)
@test shifted_opt_prob.f(reduce(vcat, θ), dat) ≈ -(loglikk(reduce(vcat, θ), dat) - _ℓmax)
@inferred shifted_opt_prob.f(reduce(vcat, θ), dat)

## Test that we can prepare the cache 
n = 2
_left_profile_vals, _right_profile_vals,
_left_param_vals, _right_param_vals,
_left_other_mles, _right_other_mles,
_combined_profiles, _combined_param_vals, _combined_other_mles,
_cache, _sub_cache = PL.prepare_cache_vectors(n, N, ranges[n], _mles)
@test _left_profile_vals == Vector{T}([])
@test _right_profile_vals == Vector{T}([])
@test _left_param_vals == Vector{T}([])
@test _right_param_vals == Vector{T}([])
@test _left_other_mles == Vector{Vector{T}}([])
@test _right_other_mles == Vector{Vector{T}}([])
@test _combined_profiles == Vector{T}([])
@test _combined_param_vals == Vector{T}([])
@test _combined_other_mles == Vector{Vector{T}}([])
@test _cache.dual_du == DiffCache(zeros(T, N)).dual_du
@test _cache.du == DiffCache(zeros(T, N)).du
@test _sub_cache == _mles[[1, 3, 4, 5]]

## Test the construction of the ProfileLikelihoodSolution 
Random.seed!(98871)
n = 300
β = [-1.0, 1.0, 0.5, 3.0]
σ = 0.05
x₁ = rand(Uniform(-1, 1), n)
x₂ = rand(Normal(1.0, 0.5), n)
X = hcat(ones(n), x₁, x₂, x₁ .* x₂)
ε = rand(Normal(0.0, σ), n)
y = X * β + ε
sse = DiffCache(zeros(n))
β_cache = DiffCache(similar(β), 10)
dat = (y, X, sse, n, β_cache)
@inline function loglik_fnc(θ, data)
    σ, β₀, β₁, β₂, β₃ = θ
    y, X, sse, n, β = data
    _sse = get_tmp(sse, θ)
    _β = get_tmp(β, θ)
    _β[1] = β₀
    _β[2] = β₁
    _β[3] = β₂
    _β[4] = β₃
    ℓℓ = -0.5n * log(2π * σ^2)
    mul!(_sse, X, _β)
    for i in eachindex(y)
        ℓℓ = ℓℓ - 0.5 / σ^2 * (y[i] - _sse[i])^2
    end
    return ℓℓ
end
θ₀ = ones(5)
prob = LikelihoodProblem(loglik_fnc, θ₀;
    data=dat,
    f_kwargs=(adtype=Optimization.AutoForwardDiff(),),
    prob_kwargs=(lb=[0.0, -5.0, -5.0, -5.0, -5.0],
        ub=[15.0, 15.0, 15.0, 15.0, 15.0]),
    syms=[:σ, :β₀, :β₁, :β₂, :β₃])
sol = mle(prob, Optim.LBFGS())
prof = profile(prob, sol, [1, 3])
@test PL.get_parameter_values(prof) == prof.parameter_values
@test PL.get_parameter_values(prof, 1) == prof.parameter_values[1]
@test PL.get_parameter_values(prof, :σ) == prof.parameter_values[1]
@test PL.get_parameter_values(prof, 3) == prof.parameter_values[3]
@test PL.get_parameter_values(prof, :β₁) == prof.parameter_values[3]
@test PL.get_profile_values(prof) == prof.profile_values
@test PL.get_profile_values(prof, 3) == prof.profile_values[3]
@test PL.get_profile_values(prof, :σ) == prof.profile_values[1]
@test PL.get_likelihood_problem(prof) == prof.likelihood_problem == prob
@test PL.get_likelihood_solution(prof) == prof.likelihood_solution == sol
@test PL.get_splines(prof) == prof.splines
@test PL.get_splines(prof, 3) == prof.splines[3]
@test PL.get_splines(prof, :σ) == prof.splines[1]
@test PL.get_confidence_intervals(prof) == prof.confidence_intervals
@test PL.get_confidence_intervals(prof, 1) == prof.confidence_intervals[1]
@test PL.get_confidence_intervals(prof, :β₁) == prof.confidence_intervals[3]
@test PL.get_other_mles(prof) == prof.other_mles
@test PL.get_other_mles(prof, 3) == prof.other_mles[3]
@test PL.get_syms(prof) == prob.syms == [:σ, :β₀, :β₁, :β₂, :β₃]
@test PL.get_syms(prof, 4) == :β₂
@test SciMLBase.sym_to_index(:σ, prof) == 1
@test SciMLBase.sym_to_index(:β₀, prof) == 2
@test SciMLBase.sym_to_index(:β₁, prof) == 3
@test SciMLBase.sym_to_index(:β₂, prof) == 4
@test SciMLBase.sym_to_index(:β₃, prof) == 5
@test PL.profiled_parameters(prof) == [1, 3]
@test PL.number_of_profiled_parameters(prof) == 2

## Test that views are working correctly on the ProfileLikelihoodSolution
i = 1
prof_view = prof[i]
@test PL.get_parent(prof_view) == prof
@test PL.get_index(prof_view) == i
@test PL.get_parameter_values(prof_view) == prof.parameter_values[i]
@test PL.get_parameter_values(prof_view, 1) == prof.parameter_values[i][1]
@test PL.get_parameter_values(prof_view, 3) == prof.parameter_values[i][3]
@test PL.get_profile_values(prof_view) == prof.profile_values[i]
@test PL.get_profile_values(prof_view, 3) == prof.profile_values[i][3]
@test PL.get_likelihood_problem(prof_view) == prof.likelihood_problem == prob
@test PL.get_likelihood_solution(prof_view) == prof.likelihood_solution == sol
@test PL.get_splines(prof_view) == prof.splines[i]
@test PL.get_confidence_intervals(prof_view) == prof.confidence_intervals[i]
@test PL.get_confidence_intervals(prof_view, 1) == prof.confidence_intervals[i][1]
@test PL.get_other_mles(prof_view) == prof.other_mles[i]
@test PL.get_other_mles(prof_view, 3) == prof.other_mles[i][3]
@test PL.get_syms(prof_view) == :σ
@test prof[:β₁] == prof[3]

## Test that we can correctly call the profiles 
x = prof.splines[i].itp.knots
@test prof_view(x) == prof(x, i) == prof.splines[i](x)

## Threads 
Random.seed!(98871)
n = 30000
β = [-1.0, 1.0, 0.5, 3.0]
σ = 0.4
x₁ = rand(Uniform(-1, 1), n)
x₂ = rand(Normal(1.0, 0.5), n)
X = hcat(ones(n), x₁, x₂, x₁ .* x₂)
ε = rand(Normal(0.0, σ), n)
y = X * β + ε
sse = DiffCache(zeros(n))
β_cache = DiffCache(similar(β), 10)
dat = (y, X, sse, n, β_cache)
@inline function loglik_fnc(θ, data)
    σ, β₀, β₁, β₂, β₃ = θ
    y, X, sse, n, β = data
    _sse = get_tmp(sse, θ)
    _β = get_tmp(β, θ)
    _β[1] = β₀
    _β[2] = β₁
    _β[3] = β₂
    _β[4] = β₃
    ℓℓ = -0.5n * log(2π * σ^2)
    mul!(_sse, X, _β)
    for i in eachindex(y)
        ℓℓ = ℓℓ - 0.5 / σ^2 * (y[i] - _sse[i])^2
    end
    return ℓℓ
end
θ₀ = ones(5)
prob = LikelihoodProblem(loglik_fnc, θ₀;
    data=dat,
    f_kwargs=(adtype=Optimization.AutoForwardDiff(),),
    prob_kwargs=(lb=[0.0, -5.0, -5.0, -5.0, -5.0],
        ub=[15.0, 15.0, 15.0, 15.0, 15.0]),
    syms=[:σ, :β₀, :β₁, :β₂, :β₃])
sol = mle(prob, Optim.LBFGS())
prof_serial = profile(prob, sol)
prof_parallel = profile(prob, sol; parallel=true)
@test all(i -> abs((prof_parallel.confidence_intervals[i].lower - prof_serial.confidence_intervals[i].lower) / prof_serial.confidence_intervals[i].lower) < 1e-2, 1:5)
@test all(i -> abs((prof_parallel.confidence_intervals[i].upper - prof_serial.confidence_intervals[i].upper) / prof_serial.confidence_intervals[i].upper) < 1e-2, 1:5)
@test all(i -> prof_parallel.parameter_values[i] ≈ prof_serial.parameter_values[i], 1:5)
@test all(i -> prof_parallel.profile_values[i] ≈ prof_serial.profile_values[i], 1:5)

## More parallel testing for a problem involving an integrator
Random.seed!(2929911002)
u₀, λ, K, n, T = 0.5, 1.0, 1.0, 100, 10.0
t = LinRange(0, T, n)
u = @. K * u₀ * exp(λ * t) / (K - u₀ + u₀ * exp(λ * t))
σ = 0.1
uᵒ = u .+ [0.0, σ * randn(length(u) - 1)...] # add some noise 
@inline function ode_fnc(u, p, t)
    local λ, K
    λ, K = p
    du = λ * u * (1 - u / K)
    return du
end
@inline function loglik_fnc2(θ, data, integrator)
    local uᵒ, n, λ, K, σ, u0
    uᵒ, n = data
    λ, K, σ, u0 = θ
    integrator.p[1] = λ
    integrator.p[2] = K
    reinit!(integrator, u0)
    solve!(integrator)
    return gaussian_loglikelihood(uᵒ, integrator.sol.u, σ, n)
end
θ₀ = [0.7, 2.0, 0.15, 0.4]
lb = [0.0, 1e-6, 1e-6, 0.0]
ub = [10.0, 10.0, 10.0, 10.0]
syms = [:λ, :K, :σ, :u₀]
prob = LikelihoodProblem(
    loglik_fnc2, θ₀, ode_fnc, u₀, (0.0, T); # u₀ is just a placeholder IC in this case
    syms=syms,
    data=(uᵒ, n),
    ode_parameters=[1.0, 1.0], # temp values for [λ, K],
    ode_kwargs=(verbose=false, saveat=t),
    f_kwargs=(adtype=Optimization.AutoFiniteDiff(),),
    prob_kwargs=(lb=lb, ub=ub),
    ode_alg=Tsit5()
)
sol = mle(prob, NLopt.LN_NELDERMEAD)
prof1 = profile(prob, sol)
prof2 = profile(prob, sol; parallel=true)

@test prof1.confidence_intervals[1].lower ≈ prof2.confidence_intervals[1].lower rtol = 1e-1
@test prof1.confidence_intervals[2].lower ≈ prof2.confidence_intervals[2].lower rtol = 1e-1
@test prof1.confidence_intervals[3].lower ≈ prof2.confidence_intervals[3].lower rtol = 1e-1
@test prof1.confidence_intervals[4].lower ≈ prof2.confidence_intervals[4].lower rtol = 1e-1
@test prof1.confidence_intervals[1].upper ≈ prof2.confidence_intervals[1].upper rtol = 1e-1
@test prof1.confidence_intervals[2].upper ≈ prof2.confidence_intervals[2].upper rtol = 1e-1
@test prof1.confidence_intervals[3].upper ≈ prof2.confidence_intervals[3].upper rtol = 1e-1
@test prof1.confidence_intervals[4].upper ≈ prof2.confidence_intervals[4].upper rtol = 1e-1
@test prof1.other_mles[1] ≈ prof2.other_mles[1] rtol = 1e-0 atol = 1e-1
@test prof1.other_mles[2] ≈ prof2.other_mles[2] rtol = 1e-1 atol = 1e-1
@test prof1.other_mles[3] ≈ prof2.other_mles[3] rtol = 1e-3 atol = 1e-1
@test prof1.other_mles[4] ≈ prof2.other_mles[4] rtol = 1e-0 atol = 1e-1
@test prof1.parameter_values[1] ≈ prof2.parameter_values[1] rtol = 1e-1
@test prof1.parameter_values[2] ≈ prof2.parameter_values[2] rtol = 1e-3
@test prof1.parameter_values[3] ≈ prof2.parameter_values[3] rtol = 1e-3
@test prof1.parameter_values[4] ≈ prof2.parameter_values[4] rtol = 1e-3
@test issorted(prof1.parameter_values[1])
@test issorted(prof1.parameter_values[2])
@test issorted(prof1.parameter_values[3])
@test issorted(prof1.parameter_values[4])
@test issorted(prof2.parameter_values[1])
@test issorted(prof2.parameter_values[2])
@test issorted(prof2.parameter_values[3])
@test issorted(prof2.parameter_values[4])
@test prof1.profile_values[1] ≈ prof2.profile_values[1] rtol = 1e-1
@test prof1.profile_values[2] ≈ prof2.profile_values[2] rtol = 1e-1
@test prof1.profile_values[3] ≈ prof2.profile_values[3] rtol = 1e-1
@test prof1.profile_values[4] ≈ prof2.profile_values[4] rtol = 1e-1
@test prof1.splines[1].itp.knots ≈ prof2.splines[1].itp.knots
@test prof1.splines[2].itp.knots ≈ prof2.splines[2].itp.knots
@test prof1.splines[3].itp.knots ≈ prof2.splines[3].itp.knots
@test prof1.splines[4].itp.knots ≈ prof2.splines[4].itp.knots

## More parallel testing for a problem involving a PDE 
# Need to setup 
a, b, c, d = 0.0, 2.0, 0.0, 2.0
n = 500
x₁ = LinRange(a, b, n)
x₂ = LinRange(b, b, n)
x₃ = LinRange(b, a, n)
x₄ = LinRange(a, a, n)
y₁ = LinRange(c, c, n)
y₂ = LinRange(c, d, n)
y₃ = LinRange(d, d, n)
y₄ = LinRange(d, c, n)
x = reduce(vcat, [x₁, x₂, x₃, x₄])
y = reduce(vcat, [y₁, y₂, y₃, y₄])
xy = [[x[i], y[i]] for i in eachindex(x)]
unique!(xy)
x = getx.(xy)
y = gety.(xy)
r = 0.07
GMSH_PATH = "./gmsh-4.9.4-Windows64/gmsh.exe"
T, adj, adj2v, DG, points, BN = generate_mesh(x, y, r; gmsh_path=GMSH_PATH)
mesh = FVMGeometry(T, adj, adj2v, DG, points, BN)
bc = ((x, y, t, u::T, p) where {T}) -> zero(T)
type = :D
BCs = BoundaryConditions(mesh, bc, type, BN)
c = 1.0
u₀ = 50.0
f = (x, y) -> y ≤ c ? u₀ : 0.0
D = (x, y, t, u, p) -> p[1]
flux = (q, x, y, t, α, β, γ, p) -> (q[1] = -α / p[1]; q[2] = -β / p[1])
R = ((x, y, t, u::T, p) where {T}) -> zero(T)
initc = @views f.(points[1, :], points[2, :])
iip_flux = true
final_time = 0.2
k = [9.0]
prob = FVMProblem(mesh, BCs; iip_flux,
    flux_function=flux, reaction_function=R,
    initial_condition=initc, final_time,
    flux_parameters=k)
alg = TRBDF2(linsolve=UMFPACKFactorization(; reuse_symbolic=false))
sol = solve(prob, alg; specialization=SciMLBase.FullSpecialize, saveat=0.01)

function compute_mass!(M::AbstractVector{T}, αβγ, sol, prob) where {T}
    mesh_area = prob.mesh.mesh_information.total_area
    fill!(M, zero(T))
    for i in eachindex(M)
        for V in FiniteVolumeMethod.get_elements(prob)
            element = FiniteVolumeMethod.get_element_information(prob.mesh, V)
            cx, cy = FiniteVolumeMethod.get_centroid(element)
            element_area = FiniteVolumeMethod.get_area(element)
            interpolant_val = eval_interpolant!(αβγ, prob, cx, cy, V, sol.u[i])
            M[i] += (element_area / mesh_area) * interpolant_val
        end
    end
    return nothing
end
M = zeros(length(sol.t))
αβγ = zeros(3)
compute_mass!(M, αβγ, sol, prob)
true_M = M ./ first(M)
Random.seed!(29922881)
σ = 0.01
true_M .+= σ * randn(length(M))
function ProfileLikelihood.construct_integrator(prob::FVMProblem, alg; ode_problem_kwargs, kwargs...)
    ode_problem = ODEProblem(prob; no_saveat=false, ode_problem_kwargs...)
    return ProfileLikelihood.construct_integrator(ode_problem, alg; kwargs...)
end
jac = float.(FiniteVolumeMethod.jacobian_sparsity(prob))
fvm_integrator = construct_integrator(prob, alg; ode_problem_kwargs=(jac_prototype=jac, saveat=0.01, parallel=true))
function loglik_fvm(θ::AbstractVector{T}, param, integrator) where {T}
    _k, _c, _u₀, _σ = θ
    (; prob) = param
    prob.flux_parameters[1] = _k
    pts = FiniteVolumeMethod.get_points(prob)
    for i in axes(pts, 2)
        pt = get_point(pts, i)
        prob.initial_condition[i] = gety(pt) ≤ _c ? _u₀ : zero(T)
    end
    reinit!(integrator, prob.initial_condition)
    solve!(integrator)
    if !SciMLBase.successful_retcode(integrator.sol)
        return typemin(T)
    end
    (; mass_data, mass_cache, shape_cache) = param
    compute_mass!(mass_cache, shape_cache, integrator.sol, prob)
    mass_cache ./= first(mass_cache)
    ℓ = @views gaussian_loglikelihood(mass_data[2:end], mass_cache[2:end], _σ, length(mass_data) - 1) # first value is 1 for both
    if isinf(ℓ)
        ℓ = -ℓ # make -typemin(T)
    end
    return ℓ
end
likprob = LikelihoodProblem(
    loglik_fvm,
    [8.54, 0.98, 29.83, 0.05],
    fvm_integrator;
    syms=[:k, :c, :u₀, :σ],
    data=(prob=prob, mass_data=true_M, mass_cache=zeros(length(true_M)), shape_cache=zeros(3)),
    f_kwargs=(adtype=Optimization.AutoFiniteDiff(),),
    prob_kwargs=(lb=[3.0, 0.0, 25.0, 1e-6],
        ub=[15.0, 2.0, 100.0, 0.2])
)
mle_sol = mle(likprob, NLopt.LN_BOBYQA)

prof1 = profile(likprob, mle_sol; ftol_abs=1e-4, ftol_rel=1e-4, xtol_abs=1e-4, xtol_rel=1e-4,
    resolution=50)
prof2 = profile(likprob, mle_sol; ftol_abs=1e-4, ftol_rel=1e-4, xtol_abs=1e-4, xtol_rel=1e-4,
    resolution=50, parallel=true)

using BenchmarkTools
#=b1 = @benchmark profile($likprob, $mle_sol; ftol_abs=$1e-4, ftol_rel=$1e-4, xtol_abs=$1e-4,
    xtol_rel=$1e-4,
    resolution=$80)
b2 = @benchmark profile($likprob, $mle_sol; ftol_abs=$1e-4, ftol_rel=$1e-4, xtol_abs=$1e-4,
    xtol_rel=$1e-4,
    resolution=$80, parallel=$true)=#

@test prof1.confidence_intervals[1].lower ≈ prof2.confidence_intervals[1].lower rtol = 1e-1
@test prof1.confidence_intervals[2].lower ≈ prof2.confidence_intervals[2].lower rtol = 1e-1
@test prof1.confidence_intervals[3].lower ≈ prof2.confidence_intervals[3].lower rtol = 1e-1
@test prof1.confidence_intervals[4].lower ≈ prof2.confidence_intervals[4].lower rtol = 1e-1
@test prof1.confidence_intervals[1].upper ≈ prof2.confidence_intervals[1].upper rtol = 1e-1
@test prof1.confidence_intervals[2].upper ≈ prof2.confidence_intervals[2].upper rtol = 1e-1
@test prof1.confidence_intervals[3].upper ≈ prof2.confidence_intervals[3].upper rtol = 1e-1
@test prof1.confidence_intervals[4].upper ≈ prof2.confidence_intervals[4].upper rtol = 1e-1
@test prof1.other_mles[1] ≈ prof2.other_mles[1] rtol = 1e-0 atol = 1e-1
@test prof1.other_mles[2] ≈ prof2.other_mles[2] rtol = 1e-1 atol = 1e-1
@test prof1.other_mles[3] ≈ prof2.other_mles[3] rtol = 1e-3 atol = 1e-1
@test prof1.other_mles[4] ≈ prof2.other_mles[4] rtol = 1e-0 atol = 1e-1
@test prof1.parameter_values[1] ≈ prof2.parameter_values[1] rtol = 1e-1
@test prof1.parameter_values[2] ≈ prof2.parameter_values[2] rtol = 1e-3
@test prof1.parameter_values[3] ≈ prof2.parameter_values[3] rtol = 1e-3
@test prof1.parameter_values[4] ≈ prof2.parameter_values[4] rtol = 1e-3
@test issorted(prof1.parameter_values[1])
@test issorted(prof1.parameter_values[2])
@test issorted(prof1.parameter_values[3])
@test issorted(prof1.parameter_values[4])
@test issorted(prof2.parameter_values[1])
@test issorted(prof2.parameter_values[2])
@test issorted(prof2.parameter_values[3])
@test issorted(prof2.parameter_values[4])
@test prof1.profile_values[1] ≈ prof2.profile_values[1] rtol = 1e-1
@test prof1.profile_values[2] ≈ prof2.profile_values[2] rtol = 1e-1
@test prof1.profile_values[3] ≈ prof2.profile_values[3] rtol = 1e-1
@test prof1.profile_values[4] ≈ prof2.profile_values[4] rtol = 1e-1
@test prof1.splines[1].itp.knots ≈ prof2.splines[1].itp.knots
@test prof1.splines[2].itp.knots ≈ prof2.splines[2].itp.knots
@test prof1.splines[3].itp.knots ≈ prof2.splines[3].itp.knots
@test prof1.splines[4].itp.knots ≈ prof2.splines[4].itp.knots

######################################################
## Example I: Multiple Linear Regression 
######################################################
## Step 1: Generate some data for the problem and define the likelihood
Random.seed!(98871)
n = 600
β = [-1.0, 1.0, 0.5, 3.0]
σ = 0.05
x₁ = rand(Uniform(-1, 1), n)
x₂ = rand(Normal(1.0, 0.5), n)
X = hcat(ones(n), x₁, x₂, x₁ .* x₂)
ε = rand(Normal(0.0, σ), n)
y = X * β + ε
sse = DiffCache(zeros(n))
β_cache = DiffCache(similar(β), 10)
dat = (y, X, sse, n, β_cache)
@inline function loglik_fnc(θ, data)
    σ, β₀, β₁, β₂, β₃ = θ
    y, X, sse, n, β = data
    _sse = get_tmp(sse, θ)
    _β = get_tmp(β, θ)
    _β[1] = β₀
    _β[2] = β₁
    _β[3] = β₂
    _β[4] = β₃
    ℓℓ = -0.5n * log(2π * σ^2)
    mul!(_sse, X, _β)
    for i in eachindex(y)
        ℓℓ = ℓℓ - 0.5 / σ^2 * (y[i] - _sse[i])^2
    end
    return ℓℓ
end

## Step 2: Define the problem 
θ₀ = ones(5)
prob = LikelihoodProblem(loglik_fnc, θ₀;
    data=dat,
    f_kwargs=(adtype=Optimization.AutoForwardDiff(),),
    prob_kwargs=(
        lb=[0.0, -Inf, -Inf, -Inf, -Inf],
        ub=Inf * ones(5)
    ),
    syms=[:σ, :β₀, :β₁, :β₂, :β₃]
)

## Step 3: Compute the MLE
sol = mle(prob, Optim.LBFGS())
df = n - (length(β) + 1)
resids = y .- X * sol[2:5]
@test sol[2:5] ≈ inv(X' * X) * X' * y # sol[i] = sol.mle[i] 
@test sol[:σ]^2 ≈ 1 / df * sum(resids .^ 2) atol = 1e-4 # symbol indexing

## Step 4: Profile 
lb = [1e-12, -5.0, -5.0, -5.0, -5.0]
ub = [15.0, 15.0, 15.0, 15.0, 15.0]
resolutions = [600, 200, 200, 200, 200] # use many points for σ
param_ranges = construct_profile_ranges(sol, lb, ub, resolutions)
prof1 = profile(prob, sol; param_ranges, parallel=true)
prof2 = profile(prob, sol; param_ranges, parallel=false)

@test prof1.confidence_intervals[1].lower ≈ prof2.confidence_intervals[1].lower rtol = 1e-3
@test prof1.confidence_intervals[2].lower ≈ prof2.confidence_intervals[2].lower rtol = 1e-3
@test prof1.confidence_intervals[3].lower ≈ prof2.confidence_intervals[3].lower rtol = 1e-3
@test prof1.confidence_intervals[4].lower ≈ prof2.confidence_intervals[4].lower rtol = 1e-3
@test prof1.confidence_intervals[1].upper ≈ prof2.confidence_intervals[1].upper rtol = 1e-2
@test prof1.confidence_intervals[2].upper ≈ prof2.confidence_intervals[2].upper rtol = 1e-3
@test prof1.confidence_intervals[3].upper ≈ prof2.confidence_intervals[3].upper rtol = 1e-3
@test prof1.confidence_intervals[4].upper ≈ prof2.confidence_intervals[4].upper rtol = 1e-3
@test prof1.other_mles[1] ≈ prof2.other_mles[1] rtol = 1e-0 atol = 1e-2
@test prof1.other_mles[2] ≈ prof2.other_mles[2] rtol = 1e-1 atol = 1e-2
@test prof1.other_mles[3] ≈ prof2.other_mles[3] rtol = 1e-3 atol = 1e-2
@test prof1.other_mles[4] ≈ prof2.other_mles[4] rtol = 1e-0 atol = 1e-2
@test prof1.parameter_values[1] ≈ prof2.parameter_values[1] rtol = 1e-3
@test prof1.parameter_values[2] ≈ prof2.parameter_values[2] rtol = 1e-3
@test prof1.parameter_values[3] ≈ prof2.parameter_values[3] rtol = 1e-3
@test prof1.parameter_values[4] ≈ prof2.parameter_values[4] rtol = 1e-3
@test issorted(prof1.parameter_values[1])
@test issorted(prof1.parameter_values[2])
@test issorted(prof1.parameter_values[3])
@test issorted(prof1.parameter_values[4])
@test issorted(prof2.parameter_values[1])
@test issorted(prof2.parameter_values[2])
@test issorted(prof2.parameter_values[3])
@test issorted(prof2.parameter_values[4])
@test prof1.profile_values[1] ≈ prof2.profile_values[1] rtol = 1e-1
@test prof1.profile_values[2] ≈ prof2.profile_values[2] rtol = 1e-1
@test prof1.profile_values[3] ≈ prof2.profile_values[3] rtol = 1e-1
@test prof1.profile_values[4] ≈ prof2.profile_values[4] rtol = 1e-1
@test prof1.splines[1].itp.knots ≈ prof2.splines[1].itp.knots
@test prof1.splines[2].itp.knots ≈ prof2.splines[2].itp.knots
@test prof1.splines[3].itp.knots ≈ prof2.splines[3].itp.knots
@test prof1.splines[4].itp.knots ≈ prof2.splines[4].itp.knots

prof = prof1

# Compare the confidence intervals
vcov_mat = sol[:σ]^2 * inv(X' * X)
for i in 1:4
    @test prof.confidence_intervals[i+1][1] ≈ sol.mle[i+1] - 1.96sqrt(vcov_mat[i, i]) atol = 1e-3
    @test prof.confidence_intervals[i+1][2] ≈ sol.mle[i+1] + 1.96sqrt(vcov_mat[i, i]) atol = 1e-3
end
rss = sum(resids .^ 2)
χ²_up = quantile(Chisq(df), 0.975)
χ²_lo = quantile(Chisq(df), 0.025)
σ_CI_exact = sqrt.(rss ./ (χ²_up, χ²_lo))
@test get_confidence_intervals(prof, :σ).lower ≈ σ_CI_exact[1] atol = 1e-3
@test ProfileLikelihood.get_upper(get_confidence_intervals(prof, :σ)) ≈ σ_CI_exact[2] atol = 1e-3

# Can also view a single parameter's results, e.g. 
prof[:β₂] # This is a ProfileLikelihoodSolutionView

# Can also evaluate the profile at a point inside the range. If 
# you want to evaluate outside the confidence interval, you need to 
# use a non-Throw extrap in the profile kwarg (see also Interpolations.jl).
# These are all the same, evaluating the profile for β₂ at β₂=0.50
prof[:β₂](0.50)
prof(0.50, :β₂)
prof(0.50, 4)

## Step 5: Visualise 
using CairoMakie, LaTeXStrings
fig = plot_profiles(prof;
    latex_names=[L"\sigma", L"\beta_0", L"\beta_1", L"\beta_2", L"\beta_3"], # default names would be of the form θᵢ
    show_mles=true,
    shade_ci=true,
    true_vals=[σ, β...],
    fig_kwargs=(fontsize=30, resolution=(2134.0f0, 906.0f0)),
    axis_kwargs=(width=600, height=300))
xlims!(fig.content[1], 0.045, 0.055) # fix the ranges
xlims!(fig.content[2], -1.025, -0.975)
xlims!(fig.content[4], 0.475, 0.525)
SAVE_FIGURE && save("figures/regression_profiles.png", fig)

# You can also plot specific parameters 
plot_profiles(prof, [1, 3]) # plot σ and β₁
plot_profiles(prof, [:σ, :β₁, :β₃]) # can use symbols 
plot_profiles(prof, 1) # can just provide an integer 
plot_profiles(prof, :β₂) # symbols work

######################################################
## Example II: Logistic ODE
######################################################
## Step 1: Generate some data for the problem and define the likelihood
Random.seed!(2929911002)
u₀, λ, K, n, T = 0.5, 1.0, 1.0, 100, 10.0
t = LinRange(0, T, n)
u = @. K * u₀ * exp(λ * t) / (K - u₀ + u₀ * exp(λ * t))
σ = 0.1
uᵒ = u .+ [0.0, σ * randn(length(u) - 1)...] # add some noise 
@inline function ode_fnc(u, p, t)
    local λ, K
    λ, K = p
    du = λ * u * (1 - u / K)
    return du
end
@inline function loglik_fnc2(θ, data, integrator)
    local uᵒ, n, λ, K, σ, u0
    uᵒ, n = data
    λ, K, σ, u0 = θ
    integrator.p[1] = λ
    integrator.p[2] = K
    reinit!(integrator, u0)
    solve!(integrator)
    return gaussian_loglikelihood(uᵒ, integrator.sol.u, σ, n)
end

## Step 2: Define the problem
θ₀ = [0.7, 2.0, 0.15, 0.4]
lb = [0.0, 1e-6, 1e-6, 0.0]
ub = [10.0, 10.0, 10.0, 10.0]
syms = [:λ, :K, :σ, :u₀]
prob = LikelihoodProblem(
    loglik_fnc2, θ₀, ode_fnc, u₀, (0.0, T); # u₀ is just a placeholder IC in this case
    syms=syms,
    data=(uᵒ, n),
    ode_parameters=[1.0, 1.0], # temp values for [λ, K],
    ode_kwargs=(verbose=false, saveat=t),
    f_kwargs=(adtype=Optimization.AutoFiniteDiff(),),
    prob_kwargs=(lb=lb, ub=ub),
    ode_alg=Tsit5()
)

## Step 3: Compute the MLE 
sol = mle(prob, NLopt.LN_BOBYQA; abstol=1e-16, reltol=1e-16)
@test PL.get_maximum(sol) ≈ 86.54963187188535
@test PL.get_mle(sol, 1) ≈ 0.7751485360202867 rtol = 1e-4
@test sol[2] ≈ 1.0214251327023145 rtol = 1e-4
@test sol[3] ≈ 0.10183154994808913 rtol = 1e-4
@test sol[4] ≈ 0.5354121514863078 rtol = 1e-4

## Step 4: Profile 
_prob = deepcopy(prob)
_sol = deepcopy(sol)
prof = profile(prob, sol; conf_level=0.9, parallel=false)
@test sol.mle == _sol.mle
@test sol.maximum == _sol.maximum # checking aliasing 
@test _prob.θ₀ == prob.θ₀
@test λ ∈ get_confidence_intervals(prof, :λ)
@test K ∈ prof.confidence_intervals[2]
@test σ ∈ get_confidence_intervals(prof[:σ])
@test u₀ ∈ get_confidence_intervals(prof, 4)

prof1 = profile(prob, sol; conf_level=0.9, parallel=false)
prof2 = profile(prob, sol; conf_level=0.9, parallel=true)

#b1 = @benchmark profile($prob, $sol; conf_level=$0.9, parallel=$true)
#b2 = @benchmark profile($prob, $sol; conf_level=$0.9, parallel=$false)

@test prof1.confidence_intervals[1].lower ≈ prof2.confidence_intervals[1].lower rtol = 1e-3
@test prof1.confidence_intervals[2].lower ≈ prof2.confidence_intervals[2].lower rtol = 1e-3
@test prof1.confidence_intervals[3].lower ≈ prof2.confidence_intervals[3].lower rtol = 1e-3
@test prof1.confidence_intervals[4].lower ≈ prof2.confidence_intervals[4].lower rtol = 1e-3
@test prof1.confidence_intervals[1].upper ≈ prof2.confidence_intervals[1].upper rtol = 1e-2
@test prof1.confidence_intervals[2].upper ≈ prof2.confidence_intervals[2].upper rtol = 1e-3
@test prof1.confidence_intervals[3].upper ≈ prof2.confidence_intervals[3].upper rtol = 1e-3
@test prof1.confidence_intervals[4].upper ≈ prof2.confidence_intervals[4].upper rtol = 1e-3
@test prof1.other_mles[1] ≈ prof2.other_mles[1] rtol = 1e-0 atol = 1e-2
@test prof1.other_mles[2] ≈ prof2.other_mles[2] rtol = 1e-1 atol = 1e-2
@test prof1.other_mles[3] ≈ prof2.other_mles[3] rtol = 1e-3 atol = 1e-2
@test prof1.other_mles[4] ≈ prof2.other_mles[4] rtol = 1e-0 atol = 1e-2
@test prof1.parameter_values[1] ≈ prof2.parameter_values[1] rtol = 1e-3
@test prof1.parameter_values[2] ≈ prof2.parameter_values[2] rtol = 1e-3
@test prof1.parameter_values[3] ≈ prof2.parameter_values[3] rtol = 1e-3
@test prof1.parameter_values[4] ≈ prof2.parameter_values[4] rtol = 1e-3
@test issorted(prof1.parameter_values[1])
@test issorted(prof1.parameter_values[2])
@test issorted(prof1.parameter_values[3])
@test issorted(prof1.parameter_values[4])
@test issorted(prof2.parameter_values[1])
@test issorted(prof2.parameter_values[2])
@test issorted(prof2.parameter_values[3])
@test issorted(prof2.parameter_values[4])
@test prof1.profile_values[1] ≈ prof2.profile_values[1] rtol = 1e-1
@test prof1.profile_values[2] ≈ prof2.profile_values[2] rtol = 1e-1
@test prof1.profile_values[3] ≈ prof2.profile_values[3] rtol = 1e-1
@test prof1.profile_values[4] ≈ prof2.profile_values[4] rtol = 1e-1
@test prof1.splines[1].itp.knots ≈ prof2.splines[1].itp.knots
@test prof1.splines[2].itp.knots ≈ prof2.splines[2].itp.knots
@test prof1.splines[3].itp.knots ≈ prof2.splines[3].itp.knots
@test prof1.splines[4].itp.knots ≈ prof2.splines[4].itp.knots

prof = prof1

## Step 5: Visualise 
using CairoMakie, LaTeXStrings
fig = plot_profiles(prof;
    latex_names=[L"\lambda", L"K", L"\sigma", L"u_0"],
    show_mles=true,
    shade_ci=true,
    true_vals=[λ, K, σ, u₀],
    fig_kwargs=(fontsize=30, resolution=(1450.0f0, 880.0f0)),
    axis_kwargs=(width=600, height=300))
SAVE_FIGURE && save("figures/logistic_example.png", fig)

######################################################
## Example III: Linear Exponential ODE with Grid Search
######################################################
## Step 1: Generate some data for the problem and define the likelihood
Random.seed!(2992999)
λ = -0.5
y₀ = 15.0
σ = 0.5
T = 5.0
n = 450
Δt = T / n
t = [j * Δt for j in 0:n]
y = y₀ * exp.(λ * t)
yᵒ = y .+ [0.0, rand(Normal(0, σ), n)...]
@inline function ode_fnc(u, p, t)
    local λ
    λ = p
    du = λ * u
    return du
end
@inline function _loglik_fnc(θ::AbstractVector{T}, data, integrator) where {T}
    local yᵒ, n, λ, σ, u0
    yᵒ, n = data
    λ, σ, u0 = θ
    integrator.p = λ
    ## Now solve the problem 
    reinit!(integrator, u0)
    solve!(integrator)
    if !SciMLBase.successful_retcode(integrator.sol)
        return typemin(T)
    end
    ℓ = -0.5(n + 1) * log(2π * σ^2)
    s = zero(T)
    @turbo @muladd for i in eachindex(yᵒ, integrator.sol.u)
        s = s + (yᵒ[i] - integrator.sol.u[i]) * (yᵒ[i] - integrator.sol.u[i])
    end
    ℓ = ℓ - 0.5s / σ^2
end

## Step 2: Define the problem
θ₀ = [-1.0, 0.5, 19.73] # will be replaced anyway
lb = [-10.0, 1e-6, 0.5]
ub = [10.0, 10.0, 25.0]
syms = [:λ, :σ, :y₀]
prob = LikelihoodProblem(
    _loglik_fnc, θ₀, ode_fnc, y₀, (0.0, T);
    syms=syms,
    data=(yᵒ, n),
    ode_parameters=1.0, # temp value for λ
    ode_kwargs=(verbose=false, saveat=t),
    f_kwargs=(adtype=Optimization.AutoFiniteDiff(),),
    prob_kwargs=(lb=lb, ub=ub),
    ode_alg=Tsit5()
)

## Step 3: Prepare the parameter grid  
regular_grid = RegularGrid(lb, ub, 50) # resolution can also be given as a vector for each parameter
@time gs = grid_search(prob, regular_grid)
@test gs[:λ] ≈ -0.612244897959183
@test gs[:σ] ≈ 0.816327448979592
@test gs[:y₀] ≈ 16.5

@time _gs = grid_search(prob, regular_grid; parallel=Val(true))
@test _gs[:λ] ≈ -0.612244897959183
@test _gs[:σ] ≈ 0.816327448979592
@test _gs[:y₀] ≈ 16.5

gs1, L1 = grid_search(prob, regular_grid; parallel=Val(true), save_vals=Val(true))
gs2, L2 = grid_search(prob, regular_grid; parallel=Val(false), save_vals=Val(true))
@test L1 ≈ L2

# Can also use LatinHypercubeSampling to avoid the dimensionality issue, although 
# you may have to be more particular with choosing the bounds to get good coverage of 
# the parameter space. An example is below.
d = 3
gens = 1000
plan, _ = LHCoptim(500, d, gens)
new_lb = [-2.0, 0.05, 10.0]
new_ub = [2.0, 0.2, 20.0]
bnds = [(new_lb[i], new_ub[i]) for i in 1:d]
parameter_vals = Matrix(scaleLHC(plan, bnds)') # transpose so that a column is a parameter set 
irregular_grid = IrregularGrid(lb, ub, parameter_vals)
gs_ir, loglik_vals_ir = grid_search(prob, irregular_grid; save_vals=Val(true))
max_lik, max_idx = findmax(loglik_vals_ir)
@test max_lik == PL.get_maximum(gs_ir)
@test parameter_vals[:, max_idx] ≈ PL.get_mle(gs_ir)

_gs_ir, _loglik_vals_ir = grid_search(prob, irregular_grid; parallel=Val(true), save_vals=Val(true))
_max_lik, _max_idx = findmax(_loglik_vals_ir)
@test _max_lik == PL.get_maximum(gs_ir)
@test parameter_vals[:, _max_idx] ≈ PL.get_mle(_gs_ir)
@test loglik_vals_ir ≈ _loglik_vals_ir
@test _max_idx == max_idx

bpar = @benchmark grid_search($prob, $irregular_grid; parallel=$Val(true), save_vals=$Val(true))
bser = @benchmark grid_search($prob, $irregular_grid; parallel=$Val(false), save_vals=$Val(true))

# Also see MultistartOptimization.jl

## Step 4: Compute the MLE, starting at the grid search solution 
prob = PL.update_initial_estimate(prob, gs)
sol = mle(prob, Optim.LBFGS())
@test PL.get_mle(sol, 1) ≈ -0.4994204745412974 rtol = 1e-2
@test sol[2] ≈ 0.5287809 rtol = 1e-2
@test sol[:y₀] ≈ 15.145175459094732 rtol = 1e-2

## Step 5: Profile 
prof = profile(prob, sol; alg=NLopt.LN_NELDERMEAD, parallel=true)
@test λ ∈ get_confidence_intervals(prof, :λ)
@test σ ∈ get_confidence_intervals(prof[:σ])
@test y₀ ∈ get_confidence_intervals(prof, 3)

prof1 = profile(prob, sol; alg=NLopt.LN_NELDERMEAD, parallel=true)
prof2 = profile(prob, sol; alg=NLopt.LN_NELDERMEAD, parallel=false)

@test prof1.confidence_intervals[1].lower ≈ prof2.confidence_intervals[1].lower rtol = 1e-3
@test prof1.confidence_intervals[2].lower ≈ prof2.confidence_intervals[2].lower rtol = 1e-3
@test prof1.confidence_intervals[3].lower ≈ prof2.confidence_intervals[3].lower rtol = 1e-3
@test prof1.confidence_intervals[1].upper ≈ prof2.confidence_intervals[1].upper rtol = 1e-2
@test prof1.confidence_intervals[2].upper ≈ prof2.confidence_intervals[2].upper rtol = 1e-3
@test prof1.confidence_intervals[3].upper ≈ prof2.confidence_intervals[3].upper rtol = 1e-3
@test prof1.other_mles[1] ≈ prof2.other_mles[1] rtol = 1e-0 atol = 1e-2
@test prof1.other_mles[2] ≈ prof2.other_mles[2] rtol = 1e-1 atol = 1e-2
@test prof1.other_mles[3] ≈ prof2.other_mles[3] rtol = 1e-3 atol = 1e-2
@test prof1.parameter_values[1] ≈ prof2.parameter_values[1] rtol = 1e-3
@test prof1.parameter_values[2] ≈ prof2.parameter_values[2] rtol = 1e-3
@test prof1.parameter_values[3] ≈ prof2.parameter_values[3] rtol = 1e-3
@test issorted(prof1.parameter_values[1])
@test issorted(prof1.parameter_values[2])
@test issorted(prof1.parameter_values[3])
@test issorted(prof2.parameter_values[1])
@test issorted(prof2.parameter_values[2])
@test issorted(prof2.parameter_values[3])
@test prof1.profile_values[1] ≈ prof2.profile_values[1] rtol = 1e-1
@test prof1.profile_values[2] ≈ prof2.profile_values[2] rtol = 1e-1
@test prof1.profile_values[3] ≈ prof2.profile_values[3] rtol = 1e-1
@test prof1.splines[1].itp.knots ≈ prof2.splines[1].itp.knots
@test prof1.splines[2].itp.knots ≈ prof2.splines[2].itp.knots
@test prof1.splines[3].itp.knots ≈ prof2.splines[3].itp.knots

#bpar = @benchmark profile($prob, $sol; alg=$NLopt.LN_NELDERMEAD, parallel=$true)
#bser = @benchmark profile($prob, $sol; alg=$NLopt.LN_NELDERMEAD, parallel=$false)

prof = prof1

## Step 5: Visualise 
using CairoMakie, LaTeXStrings
fig = plot_profiles(prof; nrow=1, ncol=3,
    latex_names=[L"\lambda", L"\sigma", L"y_0"],
    true_vals=[λ, σ, y₀],
    fig_kwargs=(fontsize=30, resolution=(2109.644f0, 444.242f0)),
    axis_kwargs=(width=600, height=300))
SAVE_FIGURE && save("figures/linear_exponential_example.png", fig)

######################################################
## Example IV: Heat equation on a square plate
######################################################
## Define the problem. See FiniteVolumeMethod.jl
a, b, c, d = 0.0, 2.0, 0.0, 2.0
n = 500
x₁ = LinRange(a, b, n)
x₂ = LinRange(b, b, n)
x₃ = LinRange(b, a, n)
x₄ = LinRange(a, a, n)
y₁ = LinRange(c, c, n)
y₂ = LinRange(c, d, n)
y₃ = LinRange(d, d, n)
y₄ = LinRange(d, c, n)
x = reduce(vcat, [x₁, x₂, x₃, x₄])
y = reduce(vcat, [y₁, y₂, y₃, y₄])
xy = [[x[i], y[i]] for i in eachindex(x)]
unique!(xy)
x = getx.(xy)
y = gety.(xy)
r = 0.022
GMSH_PATH = "./gmsh-4.9.4-Windows64/gmsh.exe"
T, adj, adj2v, DG, points, BN = generate_mesh(x, y, r; gmsh_path=GMSH_PATH)
mesh = FVMGeometry(T, adj, adj2v, DG, points, BN)
bc = ((x, y, t, u::T, p) where {T}) -> zero(T)
type = :D
BCs = BoundaryConditions(mesh, bc, type, BN)
c = 1.0
u₀ = 50.0
f = (x, y) -> y ≤ c ? u₀ : 0.0
D = (x, y, t, u, p) -> p[1]
flux = (q, x, y, t, α, β, γ, p) -> (q[1] = -α / p[1]; q[2] = -β / p[1])
R = ((x, y, t, u::T, p) where {T}) -> zero(T)
initc = @views f.(points[1, :], points[2, :])
iip_flux = true
final_time = 0.1
k = [9.0]
prob = FVMProblem(mesh, BCs; iip_flux,
    flux_function=flux, reaction_function=R,
    initial_condition=initc, final_time,
    flux_parameters=k)

## Generate some data.
alg = TRBDF2(linsolve=KLUFactorization(; reuse_symbolic=false))
sol = solve(prob, alg; specialization=SciMLBase.FullSpecialize, saveat=0.01)

## Let us compute the mass at each time and then add some noise to it
function compute_mass!(M::AbstractVector{T}, αβγ, sol, prob) where {T}
    mesh_area = prob.mesh.mesh_information.total_area
    fill!(M, zero(T))
    for i in eachindex(M)
        for V in FiniteVolumeMethod.get_elements(prob)
            element = FiniteVolumeMethod.get_element_information(prob.mesh, V)
            cx, cy = FiniteVolumeMethod.get_centroid(element)
            element_area = FiniteVolumeMethod.get_area(element)
            interpolant_val = eval_interpolant!(αβγ, prob, cx, cy, V, sol.u[i])
            M[i] += (element_area / mesh_area) * interpolant_val
        end
    end
    return nothing
end
M = zeros(length(sol.t))
αβγ = zeros(3)
compute_mass!(M, αβγ, sol, prob)
true_M = deepcopy(M)

Random.seed!(29922881)
σ = 0.1
true_M .+= σ * randn(length(M))

## We need to now construct the integrator. Here's a method for converting an FVMProblem into an integrator. 
function ProfileLikelihood.construct_integrator(prob::FVMProblem, alg; ode_problem_kwargs, kwargs...)
    ode_problem = ODEProblem(prob; no_saveat=false, ode_problem_kwargs...)
    return ProfileLikelihood.construct_integrator(ode_problem, alg; kwargs...)
end
jac = float.(FiniteVolumeMethod.jacobian_sparsity(prob))
fvm_integrator = construct_integrator(prob, alg; ode_problem_kwargs=(jac_prototype=jac, saveat=0.01, parallel=true))

## Now define the likelihood problem 
@inline function loglik_fvm(θ::AbstractVector{T}, param, integrator) where {T}
    _k, _c, _u₀ = θ
    ## Update and solve
    (; prob) = param
    prob.flux_parameters[1] = _k
    pts = FiniteVolumeMethod.get_points(prob)
    for i in axes(pts, 2)
        pt = get_point(pts, i)
        prob.initial_condition[i] = gety(pt) ≤ _c ? _u₀ : zero(T)
    end
    reinit!(integrator, prob.initial_condition)
    solve!(integrator)
    if !SciMLBase.successful_retcode(integrator.sol)
        return typemin(T)
    end
    ## Compute the mass
    (; mass_data, mass_cache, shape_cache, sigma) = param
    compute_mass!(mass_cache, shape_cache, integrator.sol, prob)
    if any(isnan, mass_cache)
        return typemin(T)
    end
    ## Done 
    ℓ = @views gaussian_loglikelihood(mass_data, mass_cache, sigma, length(mass_data))
    @show ℓ
    return ℓ
end

## Now define the problem
likprob = LikelihoodProblem(
    loglik_fvm,
    [8.54, 0.98, 29.83],
    fvm_integrator;
    syms=[:k, :c, :u₀],
    data=(prob=prob, mass_data=true_M, mass_cache=zeros(length(true_M)), shape_cache=zeros(3), sigma=σ),
    f_kwargs=(adtype=Optimization.AutoFiniteDiff(),),
    prob_kwargs=(lb=[3.0, 0.0, 0.0],
        ub=[15.0, 2.0, 250.0])
)

## Find the MLEs 
t0 = time()
mle_sol = mle(likprob, (NLopt.GN_DIRECT_L_RAND(), NLopt.LN_BOBYQA); ftol_abs=1e-8, ftol_rel=1e-8, xtol_abs=1e-8, xtol_rel=1e-8) # global, and then refine with a local algorithm
t1 = time()
@show t1 - t0

### Now profile
@time prof = profile(likprob, mle_sol; alg=NLopt.LN_BOBYQA,
    ftol_abs=1e-4, ftol_rel=1e-4, xtol_abs=1e-4, xtol_rel=1e-4,
    resolution=60)
@time _prof = profile(likprob, mle_sol; alg=NLopt.LN_BOBYQA,
    ftol_abs=1e-4, ftol_rel=1e-4, xtol_abs=1e-4, xtol_rel=1e-4,
    resolution=60, parallel=true)

prof1 = prof
prof2 = _prof

@test prof1.confidence_intervals[1].lower ≈ prof2.confidence_intervals[1].lower rtol = 1e-3
@test prof1.confidence_intervals[2].lower ≈ prof2.confidence_intervals[2].lower rtol = 1e-3
@test prof1.confidence_intervals[3].lower ≈ prof2.confidence_intervals[3].lower rtol = 1e-3
@test prof1.confidence_intervals[1].upper ≈ prof2.confidence_intervals[1].upper rtol = 1e-2
@test prof1.confidence_intervals[2].upper ≈ prof2.confidence_intervals[2].upper rtol = 1e-3
@test prof1.confidence_intervals[3].upper ≈ prof2.confidence_intervals[3].upper rtol = 1e-3
@test prof1.other_mles[1] ≈ prof2.other_mles[1] rtol = 1e-0 atol = 1e-2
@test prof1.other_mles[2] ≈ prof2.other_mles[2] rtol = 1e-1 atol = 1e-2
@test prof1.other_mles[3] ≈ prof2.other_mles[3] rtol = 1e-3 atol = 1e-2
@test prof1.parameter_values[1] ≈ prof2.parameter_values[1] rtol = 1e-3
@test prof1.parameter_values[2] ≈ prof2.parameter_values[2] rtol = 1e-3
@test prof1.parameter_values[3] ≈ prof2.parameter_values[3] rtol = 1e-3
@test issorted(prof1.parameter_values[1])
@test issorted(prof1.parameter_values[2])
@test issorted(prof1.parameter_values[3])
@test issorted(prof2.parameter_values[1])
@test issorted(prof2.parameter_values[2])
@test issorted(prof2.parameter_values[3])
@test prof1.profile_values[1] ≈ prof2.profile_values[1] rtol = 1e-1
@test prof1.profile_values[2] ≈ prof2.profile_values[2] rtol = 1e-1
@test prof1.profile_values[3] ≈ prof2.profile_values[3] rtol = 1e-1
@test prof1.splines[1].itp.knots ≈ prof2.splines[1].itp.knots
@test prof1.splines[2].itp.knots ≈ prof2.splines[2].itp.knots
@test prof1.splines[3].itp.knots ≈ prof2.splines[3].itp.knots

using CairoMakie, LaTeXStrings
fig = plot_profiles(prof; nrow=1, ncol=3,
    latex_names=[L"k", L"c", L"u_0"],
    true_vals=[k[1], c, u₀],
    fig_kwargs=(fontsize=30, resolution=(1409.096f0, 879.812f0)),
    axis_kwargs=(width=600, height=300))
scatter!(fig.content[1], get_parameter_values(prof, :k), get_profile_values(prof, :k), color=:black, markersize=9)
scatter!(fig.content[2], get_parameter_values(prof, :c), get_profile_values(prof, :c), color=:black, markersize=9)
scatter!(fig.content[3], get_parameter_values(prof, :u₀), get_profile_values(prof, :u₀), color=:black, markersize=9)
SAVE_FIGURE && save("figures/heat_pde_example.png", fig)

### Now estimate only two parameters
using StaticArraysCore
@inline function loglik_fvm_2(θ::AbstractVector{T}, param, integrator) where {T}
    _k, _c, = θ
    (; u₀) = param
    new_θ = SVector{3,T}((_k, _c, u₀))
    return loglik_fvm(new_θ, param, integrator)

end
likprob_2 = LikelihoodProblem(
    loglik_fvm_2,
    [8.54, 0.98],
    fvm_integrator;
    syms=[:k, :c],
    data=(prob=prob, mass_data=true_M, mass_cache=zeros(length(true_M)),
        shape_cache=zeros(3), sigma=σ, u₀=u₀),
    f_kwargs=(adtype=Optimization.AutoFiniteDiff(),),
    prob_kwargs=(lb=[3.0, 0.0],
        ub=[15.0, 2.0])
)

grid = RegularGrid(get_lower_bounds(likprob_2), get_upper_bounds(likprob_2), 5)
@time gs, lik_vals = grid_search(likprob_2, grid; save_vals=Val(true), parallel=Val(true));
@time _gs, _lik_vals = grid_search(likprob_2, grid; save_vals=Val(true), parallel=Val(false));
exact_lik_vals = [
    likprob_2.log_likelihood_function([k, c], likprob_2.data) for k in LinRange(3, 15, 5), c in LinRange(0, 2, 5)
]
lik_vals