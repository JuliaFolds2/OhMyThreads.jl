```@meta
EditURL = "tls.jl"
```

# [Thread-Safe Storage](@id TSS)

For some programs, it can be useful or even necessary to allocate and (re-)use memory in
your parallel code (e.g. your computation might require temporary buffers).
The following section demonstrates common issues that can arise in such a scenario and,
by means of a simple example, explains techniques to handle such cases safely.
Specifically, we'll dicuss (1) how task-local storage (TLS) can be used efficiently and
(2) how channels can be used to organize per-task buffer allocation in a thread-safe
manner.


## Sequential

Let's say that we are given two arrays of (square) matrices, `As` and `Bs`, and let's
further assume that our goal is to compute the total sum of all pairwise matrix products.
We can readily implement a (sequential) function that performs the necessary computations.

````julia
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
````

````
matmulsums (generic function with 1 method)
````

Here, we use `map` to perform the desired operation for each pair of matrices,
`A` and `B`. However, the crucial point for our discussion is that we want to use the
in-place matrix multiplication `LinearAlgebra.mul!` in conjunction with a pre-allocated
temporary buffer, the output matrix `C`. This is to avoid the temporary allocation per
"iteration" (i.e. per matrix pair) that we would get with `C = A*B`.

For later comparison, we generate some random input data and store the result.

````julia
As = [rand(512, 512) for _ in 1:512]
Bs = [rand(512, 512) for _ in 1:512]

res = matmulsums(As, Bs);
````

## The wrong way

The key idea for creating a parallel version of `matmulsums` is to replace the `map` by
OhMyThreads' parallel [`tmap`](@ref) function. However, because we re-use `C`, this isn't
entirely trivial. Someone new to parallel computing might be tempted to parallelize
`matmulsums` like this:

````julia
using OhMyThreads: tmap

function matmulsums_race(As, Bs)
    N = size(first(As), 1)
    C = Matrix{Float64}(undef, N, N)
    tmap(As, Bs) do A, B
        mul!(C, A, B)
        sum(C)
    end
end
````

````
matmulsums_race (generic function with 1 method)
````

Unfortunately, this doesn't produce the correct result.

````julia
res_race = matmulsums_race(As, Bs)
res ≈ res_race
````

````
false
````

In fact, it doesn't even always produce the same result (check for yourself)!
The reason is that there is a race condition: different parallel
tasks are trying to use the shared variable `C` simultaneously leading to
non-deterministic behavior. Let's see how we can fix this.

## The naive (and inefficient) way

A simple solution for the race condition issue above is to move the allocation of `C`
into the body of the parallel `tmap`:

````julia
function matmulsums_naive(As, Bs)
    N = size(first(As), 1)
    tmap(As, Bs) do A, B
        C = Matrix{Float64}(undef, N, N)
        mul!(C, A, B)
        sum(C)
    end
end
````

````
matmulsums_naive (generic function with 1 method)
````

In this case, a separate `C` will be allocated for each iteration such that parallel tasks
don't modify shared state anymore. Hence, we'll get the desired result.

````julia
res_naive = matmulsums_naive(As, Bs)
res ≈ res_naive
````

````
true
````

However, this variant is obviously inefficient because it is no better than just writing
`C = A*B` and thus leads to one allocation per matrix pair. We need a different way of
allocating and re-using `C` for an efficient parallel version.

## The manual (and cumbersome) way

We've seen that we can't allocate `C` once up-front (→ race condition) and also shouldn't
allocate it within the `tmap` (→ one allocation per iteration). Instead, we can assign a
separate "C" on each parallel task once and then use this task-local "C" for all
iterations (i.e. matrix pairs) for which this task is responsible.
Before we learn how to do this more conveniently, let's implement this idea of a
task-local temporary buffer (for each parallel task) manually.

````julia
using OhMyThreads: chunks, @spawn
using Base.Threads: nthreads

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
````

````
true
````

We note that this is rather cumbersome and you might not
want to write it (repeatedly). But let's take a closer look and see what's happening here.
First, we divide the number of matrix pairs into `2 * nthreads()` chunks. Then, for each of
those chunks, we spawn a parallel task that (1) allocates a task-local `C` matrix (and a
`results` vector) and (2) performs the actual computations using these pre-allocated
buffers. Finally, we `fetch` the results of the tasks and combine them. This variant works
just fine and the good news is that we can get the same behavior with less manual work.

## [The good way: Task-local storage](@id TLS)

The desire for task-local storage is quite natural with task-based multithreading. For
this reason, Julia supports this out of the box with
[`Base.task_local_storage`](https://docs.julialang.org/en/v1/base/parallel/#Base.task_local_storage-Tuple{Any}).
But instead of using this directly (which you could), we will use a convenience wrapper
around it called [`TaskLocalValue`](https://github.com/vchuravy/TaskLocalValues.jl).
This allows us to express the idea from above in few lines of code:

````julia
using OhMyThreads: TaskLocalValue

function matmulsums_tlv(As, Bs; kwargs...)
    N = size(first(As), 1)
    tlv = TaskLocalValue{Matrix{Float64}}(() -> Matrix{Float64}(undef, N, N))
    tmap(As, Bs; kwargs...) do A, B
        C = tlv[]
        mul!(C, A, B)
        sum(C)
    end
end

res_tlv = matmulsums_tlv(As, Bs)
res ≈ res_tlv
````

````
true
````

Here, `TaskLocalValue{Matrix{Float64}}(() -> Matrix{Float64}(undef, N, N))` creates a
task-local value - essentially a reference to a value in the task-local storage - that
behaves like this: The first time the task-local value is accessed from a task (`tls[]`)
it is initialized according to the provided anonymous function. Afterwards, every
following query (from the same task!) will simply lookup and return the task-local value.
This solves our issues above and leads to $O(\textrm{parallel tasks})$
(instead of $O(\textrm{iterations})$) allocations.

## Benchmark

The whole point of parallelization is increasing performance, so let's benchmark and
compare the performance of the variants that we've discussed so far.

````julia
using BenchmarkTools

@show nthreads()

@btime matmulsums($As, $Bs);
@btime matmulsums_naive($As, $Bs);
@btime matmulsums_manual($As, $Bs);
@btime matmulsums_tlv($As, $Bs);
````

````
nthreads() = 5
  3.470 s (3 allocations: 2.00 MiB)
  596.087 ms (1109 allocations: 1.00 GiB)
  584.142 ms (100 allocations: 20.03 MiB)
  598.424 ms (126 allocations: 20.02 MiB)

````

As we can see, `matmulsums_tlv` (the version using `TaskLocalValue`) isn't only convenient
but also efficient: It allocates much less memory than `matmulsums_naive`
- the difference scales with the input, i.e. `length(As)` -
and essentially the same as the manual implementation.

### Tuning the scheduling

Since the workload is uniform, we don't need load balancing. We can thus try to improve
the performance and reduce the number of allocations by choosing the number of chunks
(i.e. tasks) to match the number of Julia threads. Concretely, this
amounts to passing in `DynamicScheduler(; nchunks=nthreads())`. If we further want to
opt-out of dynamic scheduling alltogether, we can choose the `StaticScheduler()`.

````julia
using OhMyThreads: DynamicScheduler, StaticScheduler

@btime matmulsums_tlv(
    $As, $Bs; scheduler = $(DynamicScheduler(; nchunks = nthreads())));
@btime matmulsums_tlv($As, $Bs; scheduler = $(StaticScheduler()));
````

````
  590.600 ms (70 allocations: 10.02 MiB)
  595.922 ms (68 allocations: 10.02 MiB)

````

## Per-thread allocation: the bad way

The task-local solution above has one potential caveat: If we spawn many parallel tasks
(e.g. for load-balancing reasons) we need just as many task-local buffers. This can
clearly be suboptimal because only `nthreads()` tasks can run simultaneously. Hence, one
buffer per thread should actually suffice.
Of course, this raises the question of how to organize a pool of "per-thread" buffers
such that each running task always has exclusive (temporary) access to a buffer (we need
to make sure to avoid races).

A naive approach to implementing this idea is to pre-allocate an array of buffers
and then to use the `threadid()` to select a buffer for a running task.

````julia
using Base.Threads: threadid

function matmulsums_perthread_naive(As, Bs)
    N = size(first(As), 1)
    Cs = [Matrix{Float64}(undef, N, N) for _ in 1:nthreads()]
    tmap(As, Bs) do A, B
        C = Cs[threadid()]
        mul!(C, A, B)
        sum(C)
    end
end

res_pt_naive = matmulsums_perthread_naive(As, Bs)
res ≈ res_pt_naive
````

````
true
````

Unfortunately, this approach is [**generally wrong**](https://julialang.org/blog/2023/07/PSA-dont-use-threadid/). The first issue is that `threadid()`
doesn't necessarily start at 1 (and thus might return a value `> nthreads()`), in which
case `Cs[threadid()]` would be an out-of-bounds access attempt. This might be surprising
but is a simple consequence of the ordering of different kinds of Julia threads: If Julia
is started with a non-zero number of interactive threads, e.g. `--threads 5,2`, the
interactive threads come first (look at `Threads.threadpool.(1:Threads.maxthreadid())`).

But even if we account for this offset there is another, more fundamental problem, namely
**task-migration**. By default, all spawned parallel tasks are "non-sticky" and can
dynamically migrate between different Julia threads (loosely speaking, at any point in time).
This means nothing other than that **`threadid()` is not necessarily constant for a task**!
For example, imagine that task A starts on thread 4, loads the
buffer `Cs[4]`, but then gets paused, migrated, and continues executation on, say, thread 5.
Afterwards, while task A is performing `mul!(Cs[4], ...)`, a different task B might start on
(the now available) thread 4 and also read and use `Cs[4]`. This would lead to a race
condition because both tasks are mutating the same buffer.
(Note that, in practice, this - most likely 😉 - doesn't happen for the very simple example
above, but you can't rely on it!)

````julia
# Per-thread allocation: the kind of ok way
````

A simple solution for the task-migration issue is to opt-out of dynamic scheduling with
the `StaticScheduler()`. This scheduler statically assigns tasks to threads
upfront without any dynamic rescheduling (the tasks are sticky and won't migrate).

````julia
function matmulsums_perthread_static(As, Bs)
    N = size(first(As), 1)
    Cs = [Matrix{Float64}(undef, N, N) for _ in 1:nthreads()]
    tmap(As, Bs; scheduler = StaticScheduler()) do A, B
        C = Cs[threadid()]
        mul!(C, A, B)
        sum(C)
    end
end

res_pt_static = matmulsums_perthread_static(As, Bs)
res ≈ res_pt_static
````

````
true
````

However, this approach doesn't solve the offset issue and, even worse, makes the parallel code
non-composable: If we call other multithreaded functions within the `tmap` or if
our parallel `matmulsums_perthread_static` itself gets called from another parallel region
we will likely oversubscribe the Julia threads and get subpar performance. Given these
caveats, we should therefore generally take a different approach.

## Per-thread allocation: the good way (`Channel`)

Instead of storing the pre-allocated buffers in an array, we can put them into a `Channel`
which internally ensures that parallel access is safe. In this scenario, we simply `take!`
a buffer from the channel whenever we need it and `put!` it back after our computation is
done.

````julia
function matmulsums_perthread_channel(As, Bs; nbuffers = nthreads(), kwargs...)
    N = size(first(As), 1)
    chnl = Channel{Matrix{Float64}}(nbuffers)
    foreach(1:nbuffers) do _
        put!(chnl, Matrix{Float64}(undef, N, N))
    end
    tmap(As, Bs; kwargs...) do A, B
        C = take!(chnl)
        mul!(C, A, B)
        put!(chnl, C)
        sum(C)
    end
end

res_pt_channel = matmulsums_perthread_channel(As, Bs)
res ≈ res_pt_channel
````

````
true
````

## Per-thread allocation: benchmark

Let's benchmark the variants above and compare them to the task-local implementation.
We want to look at both `nchunks = nthreads()` and `nchunks = 4*nthreads()`, the latter
of which would give us dynamic load balancing (if we had a non-uniform workload).

````julia
@btime matmulsums_tlv(
    $As, $Bs; scheduler = $(DynamicScheduler(; nchunks = nthreads())));
@btime matmulsums_perthread_static($As, $Bs);
@btime matmulsums_perthread_channel(
    $As, $Bs; scheduler = $(DynamicScheduler(; nchunks = nthreads())));

@btime matmulsums_tlv(
    $As, $Bs; scheduler = $(DynamicScheduler(; nchunks = 4 * nthreads())));
@btime matmulsums_perthread_channel(
    $As, $Bs; scheduler = $(DynamicScheduler(; nchunks = 4 * nthreads())));
````

````
  584.191 ms (70 allocations: 10.02 MiB)
  592.087 ms (61 allocations: 10.02 MiB)
  586.246 ms (67 allocations: 10.02 MiB)
  591.710 ms (236 allocations: 40.04 MiB)
  582.046 ms (173 allocations: 10.03 MiB)

````

## Per-thread allocation: the another good way (`Channel`)

Above, we chose to put a limited number of buffers (e.g. `nthreads()`) into the channel
and then spawn many tasks (one per input element). Sometimes it can make sense to flip
things around and put the (many) input elements into a channel and only spawn
a limited number of tasks (e.g. `nthreads()`) with a task-local buffer.

````julia
using OhMyThreads: tmapreduce
function matmulsums_perthread_channel_flipped(As, Bs; ntasks = nthreads())
    N = size(first(As), 1)
    chnl = Channel() do chnl
        for i in 1:N
            put!(chnl, i)
        end
    end
    tmapreduce(vcat, 1:ntasks; scheduler = DynamicScheduler(; nchunks = 0)) do _ # we turn chunking off
        local C = Matrix{Float64}(undef, N, N)
        map(chnl) do i
            mul!(C, As[i], Bs[i])
            sum(C)
        end
    end
end
````

````
matmulsums_perthread_channel_flipped (generic function with 1 method)
````

Note that one caveat of this approach is that the input → task assignment, and thus the
order of the output, is non-deterministic. For this reason, we sort the output to check
for correctness

````julia
res_channel_flipped = matmulsums_perthread_channel_flipped(As, Bs)
sort(res) ≈ sort(res_channel_flipped)
````

````
true
````

---

*This page was generated using [Literate.jl](https://github.com/fredrikekre/Literate.jl).*

