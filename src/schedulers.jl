module Schedulers

using Base.Threads: nthreads

# Used to indicate that a keyword argument has not been set by the user.
# We don't use Nothing because nothing maybe sometimes be a valid user input (e.g. for init)
struct NotGiven end
isgiven(::NotGiven) = false
isgiven(::T) where {T} = true

const MaybeInteger = Union{Integer, NotGiven}

"""
Supertype for all available schedulers:

* [`DynamicScheduler`](@ref): default dynamic scheduler
* [`StaticScheduler`](@ref): low-overhead static scheduler
* [`GreedyScheduler`](@ref): greedy load-balancing scheduler
* [`SerialScheduler`](@ref): serial (non-parallel) execution
"""
abstract type Scheduler end

abstract type ChunkingMode end
struct NoChunking <: ChunkingMode end
struct FixedCount <: ChunkingMode end
struct FixedSize <: ChunkingMode end

function _chunkingstr(s::Scheduler)
    C = chunking_mode(s)
    if C == FixedCount
        cstr = "fixed count ($(s.nchunks)), :$(s.split)"
    elseif C == FixedSize
        cstr = "fixed size ($(s.chunksize)), :$(s.split)"
    elseif C == NoChunking
        cstr = "none"
    end
end

"""
    DynamicScheduler (aka :dynamic)

The default dynamic scheduler. Divides the given collection into chunks and
then spawns a task per chunk to perform the requested operation in parallel.
The tasks are assigned to threads by Julia's dynamic scheduler and are non-sticky, that is,
they can migrate between threads.

Generally preferred since it is flexible, can provide load balancing, and is composable
with other multithreaded code.

## Keyword arguments:

- `nchunks::Integer` or `ntasks::Integer` (default `nthreads(threadpool)`):
    * Determines the number of chunks (and thus also the number of parallel tasks).
    * Increasing `nchunks` can help with [load balancing](https://en.wikipedia.org/wiki/Load_balancing_(computing)), but at the expense of creating more overhead. For `nchunks <= nthreads()` there are not enough chunks for any load balancing.
    * Setting `nchunks < nthreads()` is an effective way to use only a subset of the available threads.
- `chunksize::Integer` (default not set)
    * Specifies the desired chunk size (instead of the number of chunks).
    * The options `chunksize` and `nchunks`/`ntasks` are **mutually exclusive** (only one may be a positive integer).
- `split::Symbol` (default `:batch`):
    * Determines how the collection is divided into chunks (if chunking=true). By default, each chunk consists of contiguous elements and order is maintained.
    * See [ChunkSplitters.jl](https://github.com/JuliaFolds2/ChunkSplitters.jl) for more details and available options.
    * Beware that for `split=:scatter` the order of elements isn't maintained and a reducer function must not only be associative but also **commutative**!
- `chunking::Bool` (default `true`):
    * Controls whether input elements are grouped into chunks (`true`) or not (`false`).
    * For `chunking=false`, the arguments `nchunks`/`ntasks`, `chunksize`, and `split` are ignored and input elements are regarded as "chunks" as is. Hence, there will be one parallel task spawned per input element. Note that, depending on the input, this **might spawn many(!) tasks** and can be costly!
- `threadpool::Symbol` (default `:default`):
    * Possible options are `:default` and `:interactive`.
    * The high-priority pool `:interactive` should be used very carefully since tasks on this threadpool should not be allowed to run for a long time without `yield`ing as it can interfere with [heartbeat](https://en.wikipedia.org/wiki/Heartbeat_(computing)) processes.
"""
struct DynamicScheduler{C <: ChunkingMode} <: Scheduler
    threadpool::Symbol
    nchunks::Int
    chunksize::Int
    split::Symbol

    function DynamicScheduler(threadpool::Symbol, nchunks::Integer, chunksize::Integer,
            split::Symbol; chunking::Bool = true)
        if !(threadpool in (:default, :interactive))
            throw(ArgumentError("threadpool must be either :default or :interactive"))
        end
        if !chunking
            C = NoChunking
        else
            if !(nchunks > 0 || chunksize > 0)
                throw(ArgumentError("Either nchunks/ntasks or chunksize must be a positive integer (or chunking=false)."))
            end
            if nchunks > 0 && chunksize > 0
                throw(ArgumentError("nchunks/ntasks and chunksize are mutually exclusive and only one of them may be a positive integer"))
            end
            C = chunksize > 0 ? FixedSize : FixedCount
        end
        new{C}(threadpool, nchunks, chunksize, split)
    end
end

function DynamicScheduler(;
        threadpool::Symbol = :default,
        nchunks::MaybeInteger = NotGiven(),
        ntasks::MaybeInteger = NotGiven(), # "alias" for nchunks
        chunksize::MaybeInteger = NotGiven(),
        chunking::Bool = true,
        split::Symbol = :batch)
    if !chunking
        nchunks = -1
        chunksize = -1
    else
        # only choose nchunks default if chunksize hasn't been specified
        if !isgiven(nchunks) && !isgiven(chunksize) && !isgiven(ntasks)
            nchunks = nthreads(threadpool)
            chunksize = -1
        else
            if isgiven(nchunks) && isgiven(ntasks)
                throw(ArgumentError("nchunks and ntasks are aliases and only one may be provided"))
            end
            nchunks = isgiven(nchunks) ? nchunks :
                      isgiven(ntasks) ? ntasks : -1
            chunksize = isgiven(chunksize) ? chunksize : -1
        end
    end
    DynamicScheduler(threadpool, nchunks, chunksize, split; chunking)
end

function Base.show(io::IO, mime::MIME{Symbol("text/plain")}, s::DynamicScheduler)
    print(io, "DynamicScheduler", "\n")
    cstr = _chunkingstr(s)
    println(io, "├ Chunking: ", cstr)
    print(io, "└ Threadpool: ", s.threadpool)
end

"""
    StaticScheduler (aka :static)

A static low-overhead scheduler. Divides the given collection into chunks and
then spawns a task per chunk to perform the requested operation in parallel.
The tasks are statically assigned to threads up front and are made *sticky*, that is,
they are guaranteed to stay on the assigned threads (**no task migration**).

Can sometimes be more performant than `DynamicScheduler` when the workload is (close to)
uniform and, because of the lower overhead, for small workloads.
Isn't well composable with other multithreaded code though.

## Keyword arguments:

- `nchunks::Integer` or `ntasks::Integer` (default `nthreads()`):
    * Determines the number of chunks (and thus also the number of parallel tasks).
    * Setting `nchunks < nthreads()` is an effective way to use only a subset of the available threads.
    * For `nchunks > nthreads()` the chunks will be distributed to the available threads in a round-robin fashion.
- `chunksize::Integer` (default not set)
    * Specifies the desired chunk size (instead of the number of chunks).
    * The options `chunksize` and `nchunks`/`ntasks` are **mutually exclusive** (only one may be non-zero).
- `chunking::Bool` (default `true`):
    * Controls whether input elements are grouped into chunks (`true`) or not (`false`).
    * For `chunking=false`, the arguments `nchunks`/`ntasks`, `chunksize`, and `split` are ignored and input elements are regarded as "chunks" as is. Hence, there will be one parallel task spawned per input element. Note that, depending on the input, this **might spawn many(!) tasks** and can be costly!
- `split::Symbol` (default `:batch`):
    * Determines how the collection is divided into chunks. By default, each chunk consists of contiguous elements and order is maintained.
    * See [ChunkSplitters.jl](https://github.com/JuliaFolds2/ChunkSplitters.jl) for more details and available options.
    * Beware that for `split=:scatter` the order of elements isn't maintained and a reducer function must not only be associative but also **commutative**!
"""
struct StaticScheduler{C <: ChunkingMode} <: Scheduler
    nchunks::Int
    chunksize::Int
    split::Symbol

    function StaticScheduler(nchunks::Integer, chunksize::Integer, split::Symbol;
            chunking::Bool = true)
        if !chunking
            C = NoChunking
        else
            if !(nchunks > 0 || chunksize > 0)
                throw(ArgumentError("Either nchunks/ntasks or chunksize must be a positive integer (or chunking=false)."))
            end
            if nchunks > 0 && chunksize > 0
                throw(ArgumentError("nchunks/ntasks and chunksize are mutually exclusive and only one of them may be a positive integer"))
            end
            C = chunksize > 0 ? FixedSize : FixedCount
        end
        new{C}(nchunks, chunksize, split)
    end
end

function StaticScheduler(;
        nchunks::MaybeInteger = NotGiven(),
        ntasks::MaybeInteger = NotGiven(), # "alias" for nchunks
        chunksize::MaybeInteger = NotGiven(),
        chunking::Bool = true,
        split::Symbol = :batch)
    if !chunking
        nchunks = -1
        chunksize = -1
    else
        # only choose nchunks default if chunksize hasn't been specified
        if !isgiven(nchunks) && !isgiven(chunksize) && !isgiven(ntasks)
            nchunks = nthreads(:default)
            chunksize = -1
        else
            if isgiven(nchunks) && isgiven(ntasks)
                throw(ArgumentError("nchunks and ntasks are aliases and only one may be provided"))
            end
            nchunks = isgiven(nchunks) ? nchunks :
                      isgiven(ntasks) ? ntasks : -1
            chunksize = isgiven(chunksize) ? chunksize : -1
        end
    end
    StaticScheduler(nchunks, chunksize, split; chunking)
end

function Base.show(io::IO, mime::MIME{Symbol("text/plain")}, s::StaticScheduler)
    print(io, "StaticScheduler", "\n")
    cstr = _chunkingstr(s)
    println(io, "├ Chunking: ", cstr)
    print(io, "└ Threadpool: default")
end

"""
    GreedyScheduler (aka :greedy)

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

function Base.show(io::IO, mime::MIME{Symbol("text/plain")}, s::GreedyScheduler)
    print(io, "GreedyScheduler", "\n")
    println(io, "├ Num. tasks: ", s.ntasks)
    print(io, "└ Threadpool: default")
end

"""
    SerialScheduler (aka :serial)

A scheduler for turning off any multithreading and running the code in serial. It aims to
make parallel functions like, e.g., `tmapreduce(sin, +, 1:100)` behave like their serial
counterparts, e.g., `mapreduce(sin, +, 1:100)`.
"""
struct SerialScheduler <: Scheduler
end

chunking_mode(s::Scheduler) = chunking_mode(typeof(s))
chunking_mode(::Type{DynamicScheduler{C}}) where {C} = C
chunking_mode(::Type{StaticScheduler{C}}) where {C} = C
chunking_mode(::Type{GreedyScheduler}) = NoChunking
chunking_mode(::Type{SerialScheduler}) = NoChunking

chunking_enabled(s::Scheduler) = chunking_enabled(typeof(s))
chunking_enabled(::Type{S}) where {S <: Scheduler} = chunking_mode(S) != NoChunking

scheduler_from_symbol(s::Symbol; kwargs...) = scheduler_from_symbol(Val{s}; kwargs...)
scheduler_from_symbol(::Type{Val{:static}}; kwargs...) = StaticScheduler(; kwargs...)
scheduler_from_symbol(::Type{Val{:dynamic}}; kwargs...) = DynamicScheduler(; kwargs...)
scheduler_from_symbol(::Type{Val{:greedy}}; kwargs...) = GreedyScheduler(; kwargs...)
scheduler_from_symbol(::Type{Val{:serial}}; kwargs...) = SerialScheduler(; kwargs...)
function scheduler_from_symbol(::Type{Val{T}}; kwargs...) where {T}
    # fallback
    throw(ArgumentError("unkown scheduler symbol :$T"))
end

end # module
