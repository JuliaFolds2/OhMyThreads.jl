# # [Task-Local Storage](@id TLS)
#
# For some programs, it can be useful or even necessary to allocate and (re-)use memory in
# your parallel code. The following section uses a simple example to explain how task-local
# values can be efficiently created and (re-)used.
#
# ## Sequential
#
# Let's say that we are given two arrays of (square) matrices, `As` and `Bs`, and let's
# further assume that our goal is to compute the total sum of all pairwise matrix products.
# We can readily implement a (sequential) function that performs the necessary computations.
using LinearAlgebra: mul!, BLAS
BLAS.set_num_threads(1) #  for simplicity, we turn off OpenBLAS multithreading

function matmulsums(As, Bs)
    N = size(first(As), 1)
    C = Matrix{Float64}(undef, N, N)
    map(As, Bs) do A, B
        mul!(C, A, B)
        sum(C)
    end
end

# Here, we use `map` to perform the desired operation for each pair of matrices,
# `A` and `B`. However, the crucial point for our discussion is that we use the in-place
# matrix multiplication `LinearAlgebra.mul!` in conjunction with a pre-allocated output
# matrix `C`. This is to avoid the temporary allocation per "iteration" (i.e. per matrix
# pair) that we would get with `C = A*B`.
#
# For later comparison, we generate some random input data and store the result.

As = [rand(1024, 1024) for _ in 1:64]
Bs = [rand(1024, 1024) for _ in 1:64]

res = matmulsums(As, Bs);

# ## The wrong way
#
# The key idea for creating a parallel version of `matmulsums` is to replace the `map` by
# OhMyThreads' parallel [`tmap`](@ref) function. However, because we re-use `C`, this isn't
# entirely trivial. Someone new to parallel computing might be tempted to parallelize
# `matmulsums` like so:
using OhMyThreads: tmap

function matmulsums_race(As, Bs)
    N = size(first(As), 1)
    C = Matrix{Float64}(undef, N, N)
    tmap(As, Bs) do A, B
        mul!(C, A, B)
        sum(C)
    end
end

# Unfortunately, this doesn't produce the correct result.

res_race = matmulsums_race(As, Bs)
res ≈ res_race

# In fact, It doesn't even always produce the same result (check for yourself)!
# The reason is that there is a race condition: different parallel
# tasks are trying to use the shared variable `C` simultaneously leading to
# non-deterministic behavior. Let's see how we can fix this.
#
# ## The naive (and inefficient) way
#
# A simple solution for the race condition issue above is to move the allocation of `C`
# into the body of the parallel `tmap`:
function matmulsums_naive(As, Bs)
    N = size(first(As), 1)
    tmap(As, Bs) do A, B
        C = Matrix{Float64}(undef, N, N)
        mul!(C, A, B)
        sum(C)
    end
end

# In this case, a separate `C` will be allocated for each iteration such that parallel tasks
# don't modify shared state anymore. Hence, we'll get the desired result.

res_naive = matmulsums_naive(As, Bs)
res ≈ res_naive

# However, this variant is obviously inefficient because it is no better than just writing
# `C = A*B` and thus leads to one allocation per matrix pair. We need a different way of
# allocating and re-using `C` for an efficient parallel version.
#
# ## The right way: `TaskLocalValue`
#
# We've seen that we can't allocate `C` once up-front (→ race condition) and also shouldn't
# allocate it within the `tmap` (→ one allocation per iteration). What we actually want is
# to once allocate a separate `C` on each parallel task and then re-use this **task-local**
# `C` for all iterations (i.e. matrix pairs) that said task is responsible for.
#
# The way to express this idea is `TaskLocalValue` and looks like this:
using OhMyThreads: TaskLocalValue

function matmulsums_tls(As, Bs)
    N = size(first(As), 1)
    tls = TaskLocalValue{Matrix{Float64}}(() -> Matrix{Float64}(undef, N, N))
    tmap(As, Bs) do A, B
        C = tls[]
        mul!(C, A, B)
        sum(C)
    end
end

res_tls = matmulsums_tls(As, Bs)
res ≈ res_tls

# Here, `TaskLocalValue{Matrix{Float64}}(() -> Matrix{Float64}(undef, N, N))` defines a
# task-local storage `tls` that behaves like this: The first time the storage is accessed
# (`tls[]`) from a task a task-local value is created according to the anonymous function
# (here, the task-local value will be a matrix) and stored in the storage. Afterwards,
# every other storage query from the same task(!) will simply return the task-local value.
# Hence, this is precisely what we need and will only lead to O(# parallel tasks)
# allocations.
#
# ## The manual (and cumbersome) way
#
# Before we benchmark and compare the performance of all discussed variants, let's implement
# the idea of a task-local `C` for each parallel task manually.
using OhMyThreads: chunks, @spawn
using Base.Threads: nthreads

function matmulsums_manual(As, Bs)
    N = size(first(As), 1)
    tasks = map(chunks(As; n = 2 * nthreads())) do idcs
        @spawn begin
            local C = Matrix{Float64}(undef, N, N)
            local results = Vector{Float64}(undef, length(idcs))
            for (i, idx) in enumerate(idcs)
                mul!(C, As[idx], Bs[idx])
                results[i] = sum(C)
            end
            results
        end
    end
    mapreduce(fetch, vcat, tasks)
end

res_manual = matmulsums_manual(As, Bs)
res ≈ res_manual

# The first thing to note is pretty obvious: This is very cumbersome and you probably don't
# want to write it. But let's take a closer look and see what's happening here.
# First, we divide the number of matrix pairs into `2 * nthreads()` chunks. Then, for each of
# those chunks, we spawn a parallel task that (1) allocates a task-local `C` matrix (and a
# `results` vector) and (2) performs the actual computations using these pre-allocated
# values. Finally, we `fetch` the results of the tasks and combine them.
#
# ## Benchmark
#
# The whole point of parallelization is increasing performance, so let's benchmark and
# compare the performance of the variants discussed above.

using BenchmarkTools

@show nthreads()

@btime matmulsums($As, $Bs);
@btime matmulsums_naive($As, $Bs);
@btime matmulsums_tls($As, $Bs);
@btime matmulsums_manual($As, $Bs);

# As we see, the recommened version `matmulsums_tls` is both convenient as well as
# efficient: It allocates much less memory than `matmulsums_naive` (10 vs 64 times 8 MiB)
# and is very much comparable to the manual implementation.

# ### Tuning the scheduling
#
# Since the workload is uniform, we don't need load balancing. We can thus try to use
# `DynamicScheduler(nchunks=nthreads())` and `StaticScheduler()` to improve the performance
# and/or reduce the number of allocations.

using OhMyThreads: DynamicScheduler, StaticScheduler

function matmulsums_tls_kwargs(As, Bs; kwargs...)
    N = size(first(As), 1)
    tls = TaskLocalValue{Matrix{Float64}}(() -> Matrix{Float64}(undef, N, N))
    tmap(As, Bs; kwargs...) do A, B
        C = tls[]
        mul!(C, A, B)
        sum(C)
    end
end

@btime matmulsums_tls_kwargs($As, $Bs; scheduler=$(DynamicScheduler(nchunks=nthreads())));
@btime matmulsums_tls_kwargs($As, $Bs; scheduler=$(StaticScheduler()));
