module Schedulers

using Base.Threads: nthreads

"Supertype for all schedulers"
abstract type Scheduler end

"""
The default dynamic scheduler. Divides the given collection into chunks and
then spawns a task per chunk to perform the requested operation in parallel.
The tasks are assigned to threads by Julia's dynamic scheduler and are non-sticky, that is,
they can migrate between threads.

## Keyword arguments:

- `nchunks::Int` (default `2 * nthreads()`):
    * Determines the number of chunks (and thus also the number of parallel tasks).
    * Increasing `nchunks` can help with [load balancing](https://en.wikipedia.org/wiki/Load_balancing_(computing)), but at the expense of creating more overhead. For `nchunks <= nthreads()` there are not enough chunks for any load balancing.
    * Setting `nchunks < nthreads()` is an effective way to use only a subset of the available threads.
- `split::Symbol` (default `:batch`):
    * Determines how the collection is divided into chunks. By default, each chunk consists of contiguous elements.
    * See [ChunkSplitters.jl](https://github.com/JuliaFolds2/ChunkSplitters.jl) for more details and available options.
"""
Base.@kwdef struct DynamicScheduler <: Scheduler
    nchunks::Int  = 2 * nthreads() # a multiple of nthreads to enable load balancing
    split::Symbol = :batch
end

"""
A static low-overhead scheduler. Divides the given collection into chunks and
then spawns a task per chunk to perform the requested operation in parallel.
The tasks are statically assigned to threads up front and are made *sticky*, that is,
they are guaranteed to stay on the assigned threads (**no task migration**).

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
    nchunks::Int  = nthreads()
    split::Symbol = :batch
end

"""
A greedy dynamic scheduler. The elements of the collection are first put into a `Channel`
and then dynamic, non-sticky tasks are spawned to process the elements of the channel in
parallel. Can be good choice for load-balancing slower, uneven computations, but does carry
some additional overhead.

## Keyword arguments:

- `ntasks::Int` (default `nthreads()`):
    * Determines the number of parallel tasks to be spawned.
    * Setting `nchunks < nthreads()` is an effective way to use only a subset of the available threads.
"""
Base.@kwdef struct GreedyScheduler <: Scheduler
    ntasks::Int  = nthreads()
end

end # module
