# The team schedulers: running the parallel functions on the pool of persistent worker
# tasks of ThreadTeams.jl.
#
# The parallel functions all go through `_tmapreduce` (`tforeach`, `tmap!`, `tcollect` and
# `@tasks` too) and `_tmap`, dispatching on the scheduler. The team schedulers report no
# chunking arguments (the default), so the chunking is done here (`team_nchunks`, then
# ChunkSplitters.jl for the index ranges) and only an input of at most one element runs
# serially before it gets here. A chunk function `job(c)` is then handed to
# `ThreadTeams.run_chunks` or `ThreadTeams.run_fold`.

using ThreadTeams: ThreadTeams
using OhMyThreads: TeamScheduler, GreedyTeamScheduler
using OhMyThreads.Schedulers: TeamSchedulers

# Number of elements of an iteration space (as an `Int`: the length of a `UInt` or `Int128`
# range, or of an `Int64` range on 32-bit, is not one)
@inline plength(itr::AbstractUnitRange) = Int(length(itr))
@inline plength(itr) = Int(lastindex(itr) - firstindex(itr) + 1)

# Number of chunks a parallel operation over `itr` would be split into right now: with the
# `TeamScheduler` at most one per thread of the `:default` thread pool, with the
# `GreedyTeamScheduler` as many as it asks for, and at most one per element. `1` means the
# operation runs serially (`ThreadTeams.runs_serially`).
@inline team_nchunks(itr, sched::TeamSchedulers = TeamScheduler()) =
    team_nchunks_for_length(plength(itr), sched)

@inline function team_nchunks_for_length(len::Int, s::TeamScheduler)
    len <= 1 && return 1
    ThreadTeams.runs_serially(s.schedule) && return 1
    return min(ThreadTeams.nworkers(), len)
end
@inline function team_nchunks_for_length(len::Int, g::GreedyTeamScheduler)
    len <= 1 && return 1
    ThreadTeams.runs_serially(g.schedule) && return 1
    m = g.chunksize > 0 ? cld(len, g.chunksize) :
        g.nchunks > 0 ? g.nchunks : 4 * ThreadTeams.nworkers()
    return min(m, len)
end

# The linear indices of chunk `c` of `n` contiguous chunks of `A`, split with
# ChunkSplitters.jl like the other schedulers. Chunking the index range rather than `A` itself also covers `A`s that
# ChunkSplitters does not chunk, e.g. `enumerate(chunks(...))`. `n == 1` is the whole
# collection (also when empty).
@inline function chunk_range(A, c::Int, n::Int)
    r = firstindex(A):lastindex(A)
    n == 1 && return r
    # One element per chunk (e.g. `chunks(...; n = nthreads())` on a `TeamScheduler`):
    # skip ChunkSplitters' integer divisions on every chunk's critical path
    if n == length(r)
        i = first(r) + (c - 1)
        return i:i
    end
    return r[index_chunks(r; n)[c]]
end

const ChunksInput = Union{
    ChunkSplitters.Internals.AbstractChunks,
    ChunkSplitters.Internals.Enumerate,
}

# The check for variables captured in a `Core.Box`, computed from the closure's type at
# compile time so it costs nothing (`check_boxed_captures` allocates about 100 bytes per
# call). Same error, same opt-out (`@allow_boxed_captures`), and it also looks into
# closures that the closure captures.
function boxed_fields!(out::Vector{Symbol}, @nospecialize(T), seen::Vector{Any})
    (isconcretetype(T) && !any(S -> S === T, seen)) || return out
    push!(seen, T)
    for i in 1:fieldcount(T)
        FT = fieldtype(T, i)
        if FT === Core.Box
            push!(out, fieldname(T, i))
        elseif FT !== Union{} && FT <: Function
            boxed_fields!(out, FT, seen)
        end
    end
    return out
end
@generated function boxed_captures(::Type{F}) where {F}
    return Expr(:tuple, map(QuoteNode, boxed_fields!(Symbol[], F, Any[]))...)
end
@noinline function boxed_capture_error(vars::Tuple)
    allowing_boxed_captures[] && return nothing
    throw(BoxedVariableError(Symbol[vars...]))
end
@inline check_boxed_captures() = nothing
@inline function check_boxed_captures(f, fs...)
    vars = boxed_captures(typeof(f))
    isempty(vars) || boxed_capture_error(vars)
    return check_boxed_captures(fs...)
end

# Chunk `c` of `n` of arrays with equal indices: `mapreduce` over views, task index `c`
struct MapReduceArrays{F, Op, A, K}
    f::F
    op::Op
    arrs::A
    n::Int
    kwargs::K
end
function (j::MapReduceArrays)(c::Int)
    r = chunk_range(first(j.arrs), c, j.n)
    args = map(B -> view(B, r), j.arrs)
    return mapreduce(
        promise_task_local(j.f, c), promise_task_local(j.op), args...;
        j.kwargs...
    )
end

# Chunk `c` of `n` of `tforeach` over arrays with equal indices (`outputtype = Nothing`):
# the loop over the chunk's indices written out. `MapReduceArrays` would build a view of
# every array and fold the `nothing`s of `f` with `mapreduce`; for loops of a few
# iterations per chunk that costs about as much as the iterations (35-55 ns per loop on a
# Cascade Lake). `chunk_range` gives linear indices of `first(arrs)`, and the arrays have
# the same indices (`check_all_have_same_indices`), so `B[i]` is the element that
# `view(B, r)` would yield, in the same order.
struct ForeachArrays{F, A}
    f::F
    arrs::A
    n::Int
end
function (j::ForeachArrays)(c::Int)
    r = chunk_range(first(j.arrs), c, j.n)
    f = promise_task_local(j.f, c)
    for i in r
        f(map(B -> (@inbounds B[i]), j.arrs)...)
    end
    return nothing
end

# Chunk `c` of `n` of `chunks`/`index_chunks` input: every element is one of the user's
# chunks, and its position is the task index (as with the other schedulers)
struct MapReduceItems{F, Op, I, K}
    f::F
    op::Op
    items::I
    n::Int
    kwargs::K
end
function (j::MapReduceItems)(c::Int)
    r = chunk_range(j.items, c, j.n)
    if j.kwargs isa NamedTuple{(:init,)}
        # With `init` (as for `tforeach`), `mapreduce` is the left fold
        # `op(op(init, f(item1)), f(item2))...` (`Base.mapfoldl_impl`); written out, it
        # stays off every chunk's critical path
        op = promise_task_local(j.op)
        acc = j.kwargs.init
        for i in r
            acc = op(acc, promise_task_local(j.f, i)(j.items[i]))
        end
        return acc
    end
    return mapreduce(
        i -> promise_task_local(j.f, i)(j.items[i]),
        promise_task_local(j.op), r; j.kwargs...
    )
end

# `f::F` and `op::Op`: without the static parameters, Julia would not specialize on the
# closures (they are only passed on) and would box them on every call.
function _tmapreduce(
        f::F, op::Op, Arrs, ::Type{OutputType},
        sched::TeamSchedulers,
        mapreduce_kwargs
    )::OutputType where {F, Op, OutputType}
    check_boxed_captures(f, op)
    A = first(Arrs)
    if A isa ChunksInput
        length(Arrs) == 1 ||
            throw(ArgumentError("chunks input can not be combined with other inputs"))
        job = MapReduceItems(f, op, A, team_nchunks(A, sched), mapreduce_kwargs)
    elseif A isa AbstractArray
        check_all_have_same_indices(Arrs)
        if OutputType === Nothing
            # `tforeach`: no results to combine
            job = ForeachArrays(f, Arrs, team_nchunks(A, sched))
        else
            job = MapReduceArrays(f, op, Arrs, team_nchunks(A, sched), mapreduce_kwargs)
        end
    else
        throw(
            ArgumentError(
                "$(nameof(typeof(sched))) supports arrays and " *
                    "`chunks`/`index_chunks` inputs, got $(typeof(A))"
            )
        )
    end
    job.n == 1 && return job(1)
    if OutputType === Nothing
        # `tforeach` (and `@tasks` without a reduction) has no results to combine: run the
        # chunks without `run_fold`'s partials buffer and exception handler
        ThreadTeams.run_chunks(job, job.n, sched.schedule)
        return nothing
    end
    return ThreadTeams.run_fold(job, promise_task_local(op), job.n, sched.schedule)
end

# Chunk `c` of `n` of `tmap`: the vector of results of the chunk
struct MapArrays{F, A}
    f::F
    arrs::A
    n::Int
end
function (j::MapArrays)(c::Int)
    r = chunk_range(first(j.arrs), c, j.n)
    return map(promise_task_local(j.f, c), map(B -> view(B, r), j.arrs)...)
end

struct MapItems{F, I}
    f::F
    items::I
    n::Int
end
function (j::MapItems)(c::Int)
    r = chunk_range(j.items, c, j.n)
    return map(i -> promise_task_local(j.f, i)(j.items[i]), r)
end

function map_chunks(sched::TeamSchedulers, job::J) where {J}
    job.n == 1 && return job(1)
    return ThreadTeams.run_fold(job, append!!, job.n, sched.schedule)
end

function _tmap(
        sched::TeamSchedulers, f::F, A::AbstractArray,
        _Arrs::AbstractArray...
    ) where {F}
    check_boxed_captures(f)
    Arrs = (A, _Arrs...)
    v = map_chunks(sched, MapArrays(f, Arrs, team_nchunks(A, sched)))
    return reshape(v, size(A)...)
end

function _tmap(
        sched::TeamSchedulers, f::F, A::ChunksInput,
        _Arrs::AbstractArray...
    ) where {F}
    isempty(_Arrs) ||
        throw(ArgumentError("chunks input can not be combined with other inputs"))
    check_boxed_captures(f)
    return map_chunks(sched, MapItems(f, A, team_nchunks(A, sched)))
end
