# # [Thread-Safe Storage](@id TSS)
#
# For some programs, it can be useful or even necessary to allocate and (re-)use memory in
# your parallel code (e.g. your computation might require temporary buffers).
# The following section demonstrates common issues that can arise in such a scenario and,
# by means of a simple example, explains techniques to handle such cases safely.
# Specifically, we'll dicuss (1) how task-local storage (TLS) can be used efficiently and
# (2) how channels can be used to organize per-task buffer allocation in a thread-safe
# manner.
#
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
# `A` and `B`. However, the crucial point for our discussion is that we want to use the
# in-place matrix multiplication `LinearAlgebra.mul!` in conjunction with a pre-allocated
# temporary buffer, the output matrix `C`. This is to avoid the temporary allocation per
# "iteration" (i.e. per matrix pair) that we would get with `C = A*B`.
#
# For later comparison, we generate some random input data and store the result.

As = [rand(512, 512) for _ in 1:512]
Bs = [rand(512, 512) for _ in 1:512]

res = matmulsums(As, Bs);

# ## The wrong way
#
# The key idea for creating a parallel version of `matmulsums` is to replace the `map` by
# OhMyThreads' parallel [`tmap`](@ref) function. However, because we re-use `C`, this isn't
# entirely trivial. Someone new to parallel computing might be tempted to parallelize
# `matmulsums` like this:
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

# In fact, it doesn't even always produce the same result (check for yourself)!
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
# ## The manual (and cumbersome) way
#
# We've seen that we can't allocate `C` once up-front (→ race condition) and also shouldn't
# allocate it within the `tmap` (→ one allocation per iteration). Instead, we can assign a
# separate "C" on each parallel task once and then use this task-local "C" for all
# iterations (i.e. matrix pairs) for which this task is responsible.
# Before we learn how to do this more conveniently, let's implement this idea of a
# task-local temporary buffer (for each parallel task) manually.
using OhMyThreads: chunks, @spawn
using Base.Threads: nthreads

# function matmulsums_manual(As, Bs)
#     N = size(first(As), 1)
#     tasks = map(chunks(As; n = 2 * nthreads())) do idcs
#         @spawn begin
#             local C = Matrix{Float64}(undef, N, N)
#             local results = Vector{Float64}(undef, length(idcs))
#             for (i, idx) in enumerate(idcs)
#                 mul!(C, As[idx], Bs[idx])
#                 results[i] = sum(C)
#             end
#             results
#         end
#     end
#     mapreduce(fetch, vcat, tasks)
# end
function matmulsums_manual(As, Bs)
    N = size(first(As), 1)
    tasks = map(chunks(As; n = 2 * nthreads())) do idcs
        @spawn begin
            local C = Matrix{Float64}(undef, N, N)
            map(idcs) do i
                mul!(C, As[i], Bs[i])
                sum(C)
            end
        end
    end
    mapreduce(fetch, vcat, tasks)
end

res_manual = matmulsums_manual(As, Bs)
res ≈ res_manual

# The first thing to note is pretty obvious: This is rather cumbersome and you might not
# want to write it (repeatedly). But let's take a closer look and see what's happening here.
# First, we divide the number of matrix pairs into `2 * nthreads()` chunks. Then, for each of
# those chunks, we spawn a parallel task that (1) allocates a task-local `C` matrix (and a
# `results` vector) and (2) performs the actual computations using these pre-allocated
# buffers. Finally, we `fetch` the results of the tasks and combine them. This variant works
# just fine and the good news is that we can get the same behavior with less manual work.
#
# ## [The good way: Task-local storage](@id TLS)
#
# The desire for task-local storage is quite natural with task-based multithreading. For
# this reason, Julia supports this out of the box with
# [`Base.task_local_storage`](https://docs.julialang.org/en/v1/base/parallel/#Base.task_local_storage-Tuple{Any}).
# But instead of using this directly (which you could), we will use a convenience wrapper
# around it called [`TaskLocalValue`](https://github.com/vchuravy/TaskLocalValues.jl).
# This allows us to express the idea from above in few lines of code:
using OhMyThreads: TaskLocalValue

function matmulsums_tlv(As, Bs)
    N = size(first(As), 1)
    tlv = TaskLocalValue{Matrix{Float64}}(() -> Matrix{Float64}(undef, N, N))
    tmap(As, Bs) do A, B
        C = tlv[]
        mul!(C, A, B)
        sum(C)
    end
end

res_tlv = matmulsums_tlv(As, Bs)
res ≈ res_tlv

# Here, `TaskLocalValue{Matrix{Float64}}(() -> Matrix{Float64}(undef, N, N))` creates a
# task-local value - essentially a reference to a value in the task-local storage - that
# behaves like this: The first time the task-local value is accessed from a task (`tls[]`)
# it is initialized according to the provided anonymous function. Afterwards, every
# following query (from the same task!) will simply lookup and return the task-local value.
# This solves our issues above and leads to $O(\textrm{parallel tasks})$
# (instead of $O(\textrm{iterations})$) allocations.
#
# ## Benchmark
#
# The whole point of parallelization is increasing performance, so let's benchmark and
# compare the performance of the variants that we've discussed so far.

using BenchmarkTools

@show nthreads()

@btime matmulsums($As, $Bs);
@btime matmulsums_naive($As, $Bs);
@btime matmulsums_manual($As, $Bs);
@btime matmulsums_tlv($As, $Bs);

# As we can see, `matmulsums_tlv` (the version using `TaskLocalValue`) isn't only convenient
# but also efficient: It allocates much less memory than `matmulsums_naive`
# - the difference scales with the input, i.e. `length(As)` -
# and essentially the same as the manual implementation.

# ### Tuning the scheduling
#
# Since the workload is uniform, we don't need load balancing. We can thus try to use
# `DynamicScheduler(; nchunks=nthreads())` and `StaticScheduler()` to improve the performance
# and/or reduce the number of allocations.

using OhMyThreads: DynamicScheduler, StaticScheduler

function matmulsums_tlv(As, Bs; kwargs...)
    N = size(first(As), 1)
    tlv = TaskLocalValue{Matrix{Float64}}(() -> Matrix{Float64}(undef, N, N))
    tmap(As, Bs; kwargs...) do A, B
        C = tlv[]
        mul!(C, A, B)
        sum(C)
    end
end

@btime matmulsums_tlv(
    $As, $Bs; scheduler = $(DynamicScheduler(; nchunks = nthreads())));
@btime matmulsums_tlv($As, $Bs; scheduler = $(StaticScheduler()));

#
# ## Per-thread preallocation: the bad way
#
# TODO....
#
using Base.Threads: threadid

function matmulsums_perthread_array(As, Bs; kwargs...)
    N = size(first(As), 1)
    Cs = [Matrix{Float64}(undef, N, N) for _ in 1:nthreads()]
    tmap(As, Bs; kwargs...) do A, B
        C = Cs[threadid()]
        mul!(C, A, B)
        sum(C)
    end
end

res_array = matmulsums_perthread_array(As, Bs)
res ≈ res_array

#
# TODO...
# Issues:
# * `threadid()` might not be constant per task due to task migration
# * `threadid()` (of default threads) doesn't start at 1 when using interactive threads → out of bounds access
#
# ## Per-thread preallocation: the good way (`Channel`)
#
# TODO...
#
function matmulsums_perthread_channel(As, Bs; kwargs...)
    N = size(first(As), 1)
    chnl = Channel{Matrix{Float64}}(nthreads())
    foreach(1:nthreads()) do _
        put!(chnl, Matrix{Float64}(undef, N, N))
    end
    tmap(As, Bs; kwargs...) do A, B
        C = take!(chnl)
        mul!(C, A, B)
        put!(chnl, C)
        sum(C)
    end
end

res_channel = matmulsums_perthread_channel(As, Bs)
res ≈ res_channel

#
# TODO...
#

function matmulsums_perthread_channel2(As, Bs; ntasks = nthreads())
    N = size(first(As), 1)
    chnl = Channel() do chnl
        for i in 1:N
            put!(chnl, i)
        end
    end
    tmapreduce(vcat, 1:ntasks; scheduler = DynamicScheduler(; nchunks = 0)) do _
        local C = Matrix{Float64}(undef, N, N)
        map(chnl) do i
            mul!(C, As[i], Bs[i])
            sum(C)
        end
    end
end

res_channel2 = matmulsums_perthread_channel2(As, Bs)
sort(res) ≈ sort(res_channel2) # input → task assignment (and thus output order) is non-deterministic

#
# TODO...
#

@btime matmulsums_tlv(
    $As, $Bs; scheduler = $(DynamicScheduler(; nchunks = nthreads())));
@btime matmulsums_perthread_channel(
    $As, $Bs; scheduler = $(DynamicScheduler(; nchunks = nthreads())));
@btime matmulsums_perthread_channel2($As, $Bs; ntasks = $(nthreads()));
@btime matmulsums_tlv(
    $As, $Bs; scheduler = $(DynamicScheduler(; nchunks = 4 * nthreads())));
@btime matmulsums_perthread_channel(
    $As, $Bs; scheduler = $(DynamicScheduler(; nchunks = 4 * nthreads())));
@btime matmulsums_perthread_channel2($As, $Bs; ntasks = $(4 * nthreads()));
