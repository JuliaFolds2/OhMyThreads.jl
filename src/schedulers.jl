module Schedulers

using Base.Threads: nthreads
using ChunkSplitters: Split, Consecutive, RoundRobin, ChunkSplitters

# Used to indicate that a keyword argument has not been set by the user.
# We don't use Nothing because nothing maybe sometimes be a valid user input (e.g. for init)
struct NotGiven end
isgiven(::NotGiven) = false
isgiven(::T) where {T} = true

const MaybeInteger = Union{Integer, NotGiven}

struct NoSplit <: Split end
_parse_split(split::Split) = split
function _parse_split(split::Symbol)
    split in (:consecutive, :batch) && return Consecutive()
    split in (:roundrobin, :scatter) && return RoundRobin()
    throw(ArgumentError("You've provided an unsupported value for `split`"))
end
_splitid(x::Type{<:Split}) = nameof(x) |> string |> lowercase |> Symbol
_splitid(x::Split) = _splitid(typeof(x))

"""
Supertype for all available schedulers:

* [`DynamicScheduler`](@ref): default dynamic scheduler
* [`StaticScheduler`](@ref): low-overhead static scheduler
* [`GreedyScheduler`](@ref): greedy load-balancing scheduler
* [`SerialScheduler`](@ref): serial (non-parallel) execution
"""
abstract type Scheduler end
#! A subtype of Scheduler (let's call it `S`) **must** implement:
#   - `from_symbol(::Val{:symbol})` returning exactly `S` for the given symbol.
#     (e.g. `from_symbol(::Val{:dynamic}) = DynamicScheduler`)

# To enable chunking, S **must** implement:
#   - `chunking_args(::S)::ChunkingArgs` returning the chunking arguments of the scheduler.
#     It usually is a field of the scheduler, and use the constructor
#     `ChunkingArgs` to create it (see below).

# And can optionally implement:
#   - `default_nchunks(::Type{S})` returning the default number of chunks for the scheduler.
#     if chunking is enabled. Default is `Threads.nthreads(:default)`.

from_symbol(::Val) = throw(ArgumentError("unkown scheduler symbol"))

scheduler_from_symbol(s::Symbol; kwargs...) = scheduler_from_symbol(Val(s); kwargs...)
function scheduler_from_symbol(v::Val; kwargs...)
    sched = from_symbol(v)
    return sched(; kwargs...)
end

"""
    ChunkingMode

A trait type to indicate the chunking mode of a scheduler. The following subtypes are available:

* `NoChunking`: no chunking is used
* `FixedCount`: the number of chunks is fixed
* `FixedSize`: the size of each chunk is fixed
"""
abstract type ChunkingMode end
struct NoChunking <: ChunkingMode end
struct FixedCount <: ChunkingMode end
struct FixedSize <: ChunkingMode end

chunksplitter_mode(::Type{FixedCount}) = ChunkSplitters.Internals.FixedCount
chunksplitter_mode(::Type{FixedSize}) = ChunkSplitters.Internals.FixedSize

"""
    ChunkingArgs{C, S <: Split}(n::Union{Int, Nothing}, size::Union{Int, Nothing}, minsize::Union{Int, Nothing}, split::S)
    ChunkingArgs(Sched::Type{<:Scheduler}; n = nothing, size = nothing, minsize = nothing, split::Union{Symbol, Split}; chunking)

Stores all the information needed for chunking. The type parameter `C` is the chunking mode
(`NoChunking`, `FixedSize`, or `FixedCount`). The `chunking` keyword argument is a boolean
and if true, everything is skipped and `C = NoChunking`.

Once the object is created, use the `has_fieldname(object)` function (e.g. `has_size(object)`)
to know if the field is effectively used.
"""
struct ChunkingArgs{C, S <: Split}
    n::Union{Int, Nothing}
    size::Union{Int, Nothing}
    minsize::Union{Int, Nothing}
    split::S
end
function ChunkingArgs(::Type{NoChunking})
    ChunkingArgs{NoChunking, NoSplit}(nothing, nothing, nothing, NoSplit())
end
function ChunkingArgs(
        Sched::Type{<:Scheduler};
        n = nothing,
        size = nothing,
        minsize = nothing,
        split::Union{Symbol, Split},
        chunking
)
    chunking || return ChunkingArgs(NoChunking)

    if isnothing(n) && isnothing(size)
        n = default_nchunks(Sched)
    elseif !isnothing(n) && !isnothing(size)
        throw(ArgumentError("nchunks and chunksize are mutually exclusive"))
    end
    chunking_mode = isnothing(n) ? FixedSize : FixedCount
    split = _parse_split(split)
    return ChunkingArgs{chunking_mode, typeof(split)}(n, size, minsize, split)
end

chunking_mode(::ChunkingArgs{C}) where {C} = C
has_n(ca::ChunkingArgs) = !isnothing(ca.n)
has_size(ca::ChunkingArgs) = !isnothing(ca.size)
has_split(::ChunkingArgs{C, S}) where {C, S} = S !== NoSplit
has_minsize(ca::ChunkingArgs) = !isnothing(ca.minsize)
chunking_enabled(ca::ChunkingArgs) = chunking_mode(ca) != NoChunking

function chunkingargs_to_kwargs(ca::ChunkingArgs, arg)
    minsize = !has_minsize(ca) ? nothing : min(ca.minsize, length(arg))
    return (; ca.n, ca.size, minsize, ca.split)
end

_chunkingstr(ca::ChunkingArgs{NoChunking}) = "none"
function _chunkingstr(ca::ChunkingArgs{FixedCount})
    str = "fixed count ($(ca.n)), split :$(_splitid(ca.split))"
    if has_minsize(ca)
        str = str * ", minimum chunk size  $(ca.minsize)"
    end
    str
end
function _chunkingstr(ca::ChunkingArgs{FixedSize})
    str = "fixed size ($(ca.size)), split :$(_splitid(ca.split))"
    str
end

# Link between a scheduler and its chunking arguments
# The first and only the first method must be overloaded for each scheduler
# that supports chunking.
chunking_args(::Scheduler) = ChunkingArgs(NoChunking)

nchunks(sched::Scheduler) = chunking_args(sched).n
chunksize(sched::Scheduler) = chunking_args(sched).size
chunksplit(sched::Scheduler) = chunking_args(sched).split
minchunksize(sched::Scheduler) = chunking_args(sched).minsize

has_nchunks(sched::Scheduler) = has_n(chunking_args(sched))
has_chunksize(sched::Scheduler) = has_size(chunking_args(sched))
has_chunksplit(sched::Scheduler) = has_split(chunking_args(sched))
has_minchunksize(sched::Scheduler) = has_minsize(chunking_args(sched))

function chunkingargs_to_kwargs(sched::Scheduler, arg)
    chunkingargs_to_kwargs(chunking_args(sched), arg)
end

chunking_mode(sched::Scheduler) = chunking_mode(chunking_args(sched))
chunking_enabled(sched::Scheduler) = chunking_enabled(chunking_args(sched))
_chunkingstr(sched::Scheduler) = _chunkingstr(chunking_args(sched))

"""
    default_nchunks(::Type{<:Scheduler})

Hardcoded default number of chunks, if not provided by the user. Can depend on the
kind of scheduler.
"""
function default_nchunks end
default_nchunks(::Type{<:Scheduler}) = nthreads(:default)

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
- `minchunksize::Union{Integer, Nothing}` (default `nothing`)
    * Sets a lower bound on the size of chunks. This argument takes priority over `nchunks`, so `treduce(+, 1:10; nchunks=10, minchunksize=5)` will only operate on `2` chunks for example.
- `split::Union{Symbol, OhMyThreads.Split}` (default `OhMyThreads.Consecutive()`):
    * Determines how the collection is divided into chunks (if chunking=true). By default, each chunk consists of contiguous elements and order is maintained.
    * See [ChunkSplitters.jl](https://github.com/JuliaFolds2/ChunkSplitters.jl) for more details and available options. We also allow users to pass `:consecutive` in place of `Consecutive()`, and `:roundrobin` in place of `RoundRobin()`
    * Beware that for `split=OhMyThreads.RoundRobin()` the order of elements isn't maintained and a reducer function must not only be associative but also **commutative**!
- `chunking::Bool` (default `true`):
    * Controls whether input elements are grouped into chunks (`true`) or not (`false`).
    * For `chunking=false`, the arguments `nchunks`/`ntasks`, `chunksize`, and `split` are ignored and input elements are regarded as "chunks" as is. Hence, there will be one parallel task spawned per input element. Note that, depending on the input, this **might spawn many(!) tasks** and can be costly!
- `threadpool::Symbol` (default `:default`):
    * Possible options are `:default` and `:interactive`.
    * The high-priority pool `:interactive` should be used very carefully since tasks on this threadpool should not be allowed to run for a long time without `yield`ing as it can interfere with [heartbeat](https://en.wikipedia.org/wiki/Heartbeat_(computing)) processes.
"""
struct DynamicScheduler{C <: ChunkingMode, S <: Split, threadpool} <: Scheduler
    chunking_args::ChunkingArgs{C, S}

    function DynamicScheduler(threadpool::Symbol, ca::ChunkingArgs)
        if !(threadpool in (:default, :interactive))
            throw(ArgumentError("threadpool must be either :default or :interactive"))
        end
        new{chunking_mode(ca), typeof(ca.split), threadpool}(ca)
    end
end

function DynamicScheduler(;
        threadpool::Symbol = :default,
        nchunks = nothing,
        ntasks = nothing, # "alias" for nchunks
        chunksize = nothing,
        split::Union{Split, Symbol} = Consecutive(),
        minchunksize = nothing,
        chunking::Bool = true
)
    if !isnothing(ntasks)
        if !isnothing(nchunks)
            throw(ArgumentError("For the dynamic scheduler, nchunks and ntasks are aliases and only one may be provided"))
        end
        nchunks = ntasks
    end
    ca = ChunkingArgs(DynamicScheduler;
        n = nchunks, size = chunksize, minsize = minchunksize, split, chunking)
    return DynamicScheduler(threadpool, ca)
end
from_symbol(::Val{:dynamic}) = DynamicScheduler
chunking_args(sched::DynamicScheduler) = sched.chunking_args
threadpool(::DynamicScheduler{C, S, T}) where {C, S, T} = T

function Base.show(io::IO, mime::MIME{Symbol("text/plain")}, s::DynamicScheduler)
    print(io, "DynamicScheduler", "\n")
    cstr = _chunkingstr(s.chunking_args)
    println(io, "├ Chunking: ", cstr)
    print(io, "└ Threadpool: ", threadpool(s))
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
- `minchunksize::Union{Integer, Nothing}` (default `nothing`)
    * Sets a lower bound on the size of chunks. This argument takes priority over `nchunks`, so `treduce(+, 1:10; nchunks=10, minchunksize=5)` will only operate on `2` chunks for example.
- `chunking::Bool` (default `true`):
    * Controls whether input elements are grouped into chunks (`true`) or not (`false`).
    * For `chunking=false`, the arguments `nchunks`/`ntasks`, `chunksize`, and `split` are ignored and input elements are regarded as "chunks" as is. Hence, there will be one parallel task spawned per input element. Note that, depending on the input, this **might spawn many(!) tasks** and can be costly!
- `split::Union{Symbol, OhMyThreads.Split}` (default `OhMyThreads.Consecutive()`):
    * Determines how the collection is divided into chunks. By default, each chunk consists of contiguous elements and order is maintained.
    * See [ChunkSplitters.jl](https://github.com/JuliaFolds2/ChunkSplitters.jl) for more details and available options. We also allow users to pass `:consecutive` in place of `Consecutive()`, and `:roundrobin` in place of `RoundRobin()`
    * Beware that for `split=OhMyThreads.RoundRobin()` the order of elements isn't maintained and a reducer function must not only be associative but also **commutative**!
"""
struct StaticScheduler{C <: ChunkingMode, S <: Split} <: Scheduler
    chunking_args::ChunkingArgs{C, S}
end

function StaticScheduler(;
        nchunks = nothing,
        ntasks = nothing, # "alias" for nchunks
        chunksize = nothing,
        minchunksize = nothing,
        split::Union{Split, Symbol} = Consecutive(),
        chunking::Bool = true
)
    if !isnothing(ntasks)
        if !isnothing(nchunks)
            throw(ArgumentError("For the static scheduler, nchunks and ntasks are aliases and only one may be provided"))
        end
        nchunks = ntasks
    end
    ca = ChunkingArgs(StaticScheduler;
        n = nchunks, size = chunksize, minsize = minchunksize, split, chunking)
    return StaticScheduler(ca)
end
from_symbol(::Val{:static}) = StaticScheduler
chunking_args(sched::StaticScheduler) = sched.chunking_args

function Base.show(io::IO, mime::MIME{Symbol("text/plain")}, s::StaticScheduler)
    print(io, "StaticScheduler", "\n")
    cstr = _chunkingstr(s.chunking_args)
    println(io, "├ Chunking: ", cstr)
    print(io, "└ Threadpool: default")
end

"""
    GreedyScheduler (aka :greedy)

A greedy dynamic scheduler. The elements are put into a shared workqueue and dynamic,
non-sticky, tasks are spawned to process the elements of the queue with each task taking a new
element from the queue as soon as the previous one is done.

Note that elements are processed in a non-deterministic order, and thus a potential reducing
function **must** be [commutative](https://en.wikipedia.org/wiki/Commutative_property) in
addition to being associative, or you could get incorrect results!

Can be good choice for load-balancing slower, uneven computations, but does carry
some additional overhead.

## Keyword arguments:

- `ntasks::Int` (default `nthreads()`):
    * Determines the number of parallel tasks to be spawned.
    * Setting `ntasks < nthreads()` is an effective way to use only a subset of the available threads.
- `chunking::Bool` (default `false`):
    * Controls whether input elements are grouped into chunks (`true`) or not (`false`) before put into the shared workqueue. This can improve the performance especially if there are many iterations each of which are computationally cheap.
    * If `nchunks` or `chunksize` are explicitly specified, `chunking` will be automatically set to `true`.
- `nchunks::Integer` (default `10 * nthreads()`):
    * Determines the number of chunks (that will eventually be put into the shared workqueue).
    * Increasing `nchunks` can help with [load balancing](https://en.wikipedia.org/wiki/Load_balancing_(computing)). For `nchunks <= nthreads()` there are not enough chunks for any load balancing.
- `chunksize::Integer` (default not set)
    * Specifies the desired chunk size (instead of the number of chunks).
    * The options `chunksize` and `nchunks` are **mutually exclusive** (only one may be a positive integer).
- `minchunksize::Union{Integer, Nothing}` (default `nothing`)
    * Sets a lower bound on the size of chunks. This argument takes priority over `nchunks`, so `treduce(+, 1:10; nchunks=10, minchunksize=5)` will only operate on `2` chunks for example.
- `split::Union{Symbol, OhMyThreads.Split}` (default `OhMyThreads.RoundRobin()`):
    * Determines how the collection is divided into chunks (if chunking=true).
    * See [ChunkSplitters.jl](https://github.com/JuliaFolds2/ChunkSplitters.jl) for more details and available options. We also allow users to pass `:consecutive` in place of `Consecutive()`, and `:roundrobin` in place of `RoundRobin()`
"""
struct GreedyScheduler{C <: ChunkingMode, S <: Split} <: Scheduler
    ntasks::Int
    chunking_args::ChunkingArgs{C, S}

    function GreedyScheduler(ntasks::Integer, ca::ChunkingArgs)
        ntasks > 0 || throw(ArgumentError("ntasks must be a positive integer"))
        return new{chunking_mode(ca), typeof(ca.split)}(ntasks, ca)
    end
end

function GreedyScheduler(;
        ntasks::Integer = nthreads(),
        nchunks = nothing,
        chunksize = nothing,
        minchunksize = nothing,
        split::Union{Split, Symbol} = RoundRobin(),
        chunking::Bool = false
)
    if !(isnothing(nchunks) && isnothing(chunksize))
        chunking = true
    end
    ca = ChunkingArgs(GreedyScheduler;
        n = nchunks, size = chunksize, minsize = minchunksize, split, chunking)
    return GreedyScheduler(ntasks, ca)
end
from_symbol(::Val{:greedy}) = GreedyScheduler
chunking_args(sched::GreedyScheduler) = sched.chunking_args
default_nchunks(::Type{GreedyScheduler}) = 10 * nthreads(:default)

function Base.show(io::IO, mime::MIME{Symbol("text/plain")}, s::GreedyScheduler)
    print(io, "GreedyScheduler", "\n")
    println(io, "├ Num. tasks: ", s.ntasks)
    cstr = _chunkingstr(s)
    println(io, "├ Chunking: ", cstr)
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
from_symbol(::Val{:serial}) = SerialScheduler

end # module
