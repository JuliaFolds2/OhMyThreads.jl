module Schedulers

using Base.Threads: nthreads

"""
Supertype for all available schedulers:

* [`DynamicScheduler`](@ref): default dynamic scheduler
* [`StaticScheduler`](@ref): low-overhead static scheduler
* [`GreedyScheduler`](@ref): greedy load-balancing scheduler
* [`SpawnAllScheduler`](@ref): `@spawn` one task per element
"""
abstract type Scheduler end

"""
The default dynamic scheduler. Divides the given collection into chunks and
then spawns a task per chunk to perform the requested operation in parallel.
The tasks are assigned to threads by Julia's dynamic scheduler and are non-sticky, that is,
they can migrate between threads.

Generally preferred since it is flexible, can provide load balancing, and is composable
with other multithreaded code.

## Keyword arguments:

- `nchunks::Int` (default `2 * nthreads(threadpool)`):
    * Determines the number of chunks (and thus also the number of parallel tasks).
    * Increasing `nchunks` can help with [load balancing](https://en.wikipedia.org/wiki/Load_balancing_(computing)), but at the expense of creating more overhead. For `nchunks <= nthreads()` there are not enough chunks for any load balancing.
    * Setting `nchunks < nthreads()` is an effective way to use only a subset of the available threads.
- `split::Symbol` (default `:batch`):
    * Determines how the collection is divided into chunks. By default, each chunk consists of contiguous elements.
    * See [ChunkSplitters.jl](https://github.com/JuliaFolds2/ChunkSplitters.jl) for more details and available options.
- `threadpool::Symbol` (default `:default`):
    * Possible options are `:default` and `:interactive`.
    * The high-priority pool `:interactive` should be used very carefully since tasks on this threadpool should not be allowed to run for a long time without `yield`ing as it can interfere with [heartbeat](https://en.wikipedia.org/wiki/Heartbeat_(computing)) processes.
"""
Base.@kwdef struct DynamicScheduler <: Scheduler
    threadpool::Symbol = :default
    nchunks::Int = 2 * nthreads(threadpool) # a multiple of nthreads to enable load balancing
    split::Symbol = :batch

    function DynamicScheduler(threadpool::Symbol, nchunks::Int, split::Symbol)
        threadpool in (:default, :interactive) ||
            throw(ArgumentError("threadpool must be either :default or :interactive"))
        nchunks > 0 || throw(ArgumentError("nchunks must be a positive integer"))
        new(threadpool, nchunks, split)
    end
end

"""
A static low-overhead scheduler. Divides the given collection into chunks and
then spawns a task per chunk to perform the requested operation in parallel.
The tasks are statically assigned to threads up front and are made *sticky*, that is,
they are guaranteed to stay on the assigned threads (**no task migration**).

Can sometimes be more performant than `DynamicScheduler` when the workload is (close to)
uniform and, because of the lower overhead, for small workloads.
Isn't well composable with other multithreaded code though.

## Keyword arguments:

- `nchunks::Int` (default `nthreads()`):
    * Determines the number of chunks (and thus also the number of parallel tasks).
    * Setting `nchunks < nthreads()` is an effective way to use only a subset of the available threads.
    * Currently, `nchunks > nthreads()` **isn't officialy supported** but, for now, will fall back to `nchunks = nthreads()`.
- `split::Symbol` (default `:batch`):
    * Determines how the collection is divided into chunks. By default, each chunk consists of contiguous elements.
    * See [ChunkSplitters.jl](https://github.com/JuliaFolds2/ChunkSplitters.jl) for more details and available options.
"""
Base.@kwdef struct StaticScheduler <: Scheduler
    nchunks::Int = nthreads()
    split::Symbol = :batch

    function StaticScheduler(nchunks::Int, split::Symbol)
        nchunks > 0 || throw(ArgumentError("nchunks must be a positive integer"))
        new(nchunks, split)
    end
end

"""
A greedy dynamic scheduler. The elements of the collection are first put into a `Channel`
and then dynamic, non-sticky tasks are spawned to process channel content in parallel.

Note that elements are processed in a non-deterministic order, and thus a potential reducing
function **must** be [commutative](https://en.wikipedia.org/wiki/Commutative_property) in
addition to being associative, or you could get incorrect results!

Can be good choice for load-balancing slower, uneven computations, but does carry
some additional overhead.

## Keyword arguments:

- `ntasks::Int` (default `nthreads()`):
    * Determines the number of parallel tasks to be spawned.
    * Setting `nchunks < nthreads()` is an effective way to use only a subset of the available threads.
"""
Base.@kwdef struct GreedyScheduler <: Scheduler
    ntasks::Int = nthreads()

    function GreedyScheduler(ntasks::Int)
        ntasks > 0 || throw(ArgumentError("ntasks must be a positive integer"))
        new(ntasks)
    end
end

Base.@kwdef struct SpawnAllScheduler <: Scheduler
    threadpool::Symbol = :default

    function SpawnAllScheduler(threadpool::Symbol)
        threadpool in (:default, :interactive) ||
            throw(ArgumentError("threadpool must be either :default or :interactive"))
        new(threadpool)
    end
end

end # module
