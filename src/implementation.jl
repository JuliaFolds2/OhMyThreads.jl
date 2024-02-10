module Implementation

import OhMyThreads: treduce, tmapreduce, treducemap, tforeach, tmap, tmap!, tcollect

using OhMyThreads: StableTasks, chunks, @spawn, @spawnat
using OhMyThreads.Tools: nthtid
using OhMyThreads: Scheduler,
    chunking_enabled, DynamicScheduler, StaticScheduler, GreedyScheduler, SpawnAllScheduler
using Base: @propagate_inbounds
using Base.Threads: nthreads, @threads

using BangBang: BangBang, append!!

using ChunkSplitters: ChunkSplitters

function tmapreduce(f, op, Arrs...;
        scheduler::Scheduler = DynamicScheduler(),
        outputtype::Type = Any,
        mapreduce_kwargs...)
    min_kwarg_len = haskey(mapreduce_kwargs, :init) ? 1 : 0
    if length(mapreduce_kwargs) > min_kwarg_len
        tmapreduce_kwargs_err(; mapreduce_kwargs...)
    end
    _tmapreduce(f, op, Arrs, outputtype, scheduler, mapreduce_kwargs)
end

@noinline function tmapreduce_kwargs_err(; init = nothing, kwargs...)
    error("got unsupported keyword arguments: $((;kwargs...,)) ")
end

treducemap(op, f, A...; kwargs...) = tmapreduce(f, op, A...; kwargs...)

# DynamicScheduler: AbstractArray/Generic
function _tmapreduce(f,
        op,
        Arrs,
        ::Type{OutputType},
        scheduler::DynamicScheduler,
        mapreduce_kwargs)::OutputType where {OutputType}
    (; nchunks, split, threadpool) = scheduler
    check_all_have_same_indices(Arrs)
    if chunking_enabled(scheduler)
        tasks = map(chunks(first(Arrs); n = nchunks, split)) do inds
            args = map(A -> view(A, inds), Arrs)
            @spawn threadpool mapreduce(f, op, args...; $mapreduce_kwargs...)
        end
        mapreduce(fetch, op, tasks)
    else
        tasks = map(eachindex(first(Arrs))) do i
            args = map(A -> @inbounds(A[i]), Arrs)
            @spawn threadpool f(args...)
        end
        mapreduce(fetch, op, tasks; mapreduce_kwargs...)
    end
end

# DynamicScheduler: ChunkSplitters.Chunk
function _tmapreduce(f,
        op,
        Arrs::Tuple{ChunkSplitters.Chunk{Vector{Float64}}}, # we don't support multiple chunks for now
        ::Type{OutputType},
        scheduler::DynamicScheduler,
        mapreduce_kwargs)::OutputType where {OutputType}
    (; nchunks, split, threadpool) = scheduler
    if chunking_enabled(scheduler)
        @warn("You passed in a ChunkSplitters.Chunk but also a scheduler that has "*
              "chunking enabled. Will turn off internal chunking to proceed.\n"*
              "To avoid this warning, try to turn off chunking (`nchunks=0`), use a "*
              "different scheduler, or pass in `collect(chunks(...))`.")
        # we don't have to do anything here but just use the no-chunking version below
    end
    tasks = map(only(Arrs)) do idcs
        @spawn threadpool f(idcs)
    end
    mapreduce(fetch, op, tasks; mapreduce_kwargs...)
end

# SpawnAllScheduler: AbstractArray
function _tmapreduce(f,
        op,
        Arrs,
        ::Type{OutputType},
        scheduler::SpawnAllScheduler,
        mapreduce_kwargs)::OutputType where {OutputType}
    (; threadpool) = scheduler
    check_all_have_same_indices(Arrs)
    tasks = map(eachindex(first(Arrs))) do i
        args = map(A -> @inbounds(A[i]), Arrs)
        @spawn threadpool f(args...)
    end
    mapreduce(fetch, op, tasks; mapreduce_kwargs...)
end

# StaticScheduler
function _tmapreduce(f,
        op,
        Arrs,
        ::Type{OutputType},
        scheduler::StaticScheduler,
        mapreduce_kwargs) where {OutputType}
    (; nchunks, split) = scheduler
    check_all_have_same_indices(Arrs)
    n = min(nthreads(), nchunks) # We could implement strategies, like round-robin, in the future
    tasks = map(enumerate(chunks(first(Arrs); n, split))) do (c, inds)
        tid = @inbounds nthtid(c)
        args = map(A -> view(A, inds), Arrs)
        @spawnat tid mapreduce(f, op, args...; mapreduce_kwargs...)
    end
    mapreduce(fetch, op, tasks)
end

# GreedyScheduler
function _tmapreduce(f,
        op,
        Arrs,
        ::Type{OutputType},
        scheduler::GreedyScheduler,
        mapreduce_kwargs)::OutputType where {OutputType}
    ntasks_desired = scheduler.ntasks
    if Base.IteratorSize(first(Arrs)) isa Base.SizeUnknown
        ntasks = ntasks_desired
        ch_len = 0
    else
        check_all_have_same_indices(Arrs)
        ntasks = min(length(first(Arrs)), ntasks_desired)
        ch_len = length(first(Arrs))
    end
    ch = Channel{Tuple{eltype.(Arrs)...}}(ch_len; spawn = true) do ch
        for args in zip(Arrs...)
            put!(ch, args)
        end
    end
    tasks = map(1:ntasks) do _
        @spawn mapreduce(op, ch; mapreduce_kwargs...) do args
            f(args...)
        end
    end
    mapreduce(fetch, op, tasks; mapreduce_kwargs...)
end

function check_all_have_same_indices(Arrs)
    let A = first(Arrs), Arrs = Arrs[2:end]
        if !all(B -> eachindex(A) == eachindex(B), Arrs)
            error("The indices of the input arrays must match the indices of the output array.")
        end
    end
end

#-------------------------------------------------------------

function treduce(op, A...; kwargs...)
    tmapreduce(identity, op, A...; kwargs...)
end

#-------------------------------------------------------------

function tforeach(f, A...; kwargs...)::Nothing
    tmapreduce(f, (l, r) -> l, A...; kwargs..., init = nothing, outputtype = Nothing)
end

#-------------------------------------------------------------

function tmap(f, ::Type{T}, A::AbstractArray, _Arrs::AbstractArray...; kwargs...) where {T}
    Arrs = (A, _Arrs...)
    tmap!(f, similar(A, T), Arrs...; kwargs...)
end

function tmap(f,
        A::Union{AbstractArray, ChunkSplitters.Chunk},
        _Arrs::AbstractArray...;
        scheduler::Scheduler = DynamicScheduler(),
        kwargs...)
    if scheduler isa GreedyScheduler
        error("Greedy scheduler isn't supported with `tmap` unless you provide an `OutputElementType` argument, since the greedy schedule requires a commutative reducing operator.")
    end
    if chunking_enabled(scheduler) && hasfield(typeof(scheduler), :split) &&
       scheduler.split != :batch
        error("Only `split == :batch` is supported because the parallel operation isn't commutative. (Scheduler: $scheduler)")
    end
    if A isa ChunkSplitters.Chunk && scheduler isa DynamicScheduler
        @warn("You passed in a ChunkSplitters.Chunk but also a `DynamicScheduler` that has "*
              "chunking enabled. Will turn off internal chunking to proceed.\n"*
              "To avoid this warning, try to turn off chunking (`nchunks=0`), use a "*
              "different scheduler, or pass in `collect(chunks(...))`.")
        (; threadpool) = scheduler
        scheduler = DynamicScheduler(; nchunks = 0, threadpool)
    end

    Arrs = (A, _Arrs...)
    check_all_have_same_indices(Arrs)
    _tmap(scheduler, f, A, _Arrs...; kwargs...)
end

# w/o chunking (SpawnAllScheduler, DynamicScheduler{false})
function _tmap(scheduler::Union{SpawnAllScheduler, DynamicScheduler{false}},
        f,
        A::Union{AbstractArray, ChunkSplitters.Chunk},
        _Arrs::AbstractArray...;
        kwargs...)
    (; threadpool) = scheduler
    if A isa ChunkSplitters.Chunk
        tasks = map(A) do idcs
            @spawn threadpool f(idcs)
        end
        v = map(fetch, tasks)
    else
        Arrs = (A, _Arrs...)
        tasks = map(eachindex(A)) do i
            @spawn threadpool begin
                args = map(A -> A[i], Arrs)
                f(args...)
            end
        end
        v = map(fetch, tasks)
        reshape(v, size(A)...)
    end
end

# w/ chunking
function _tmap(scheduler::Scheduler,
        f,
        A::AbstractArray,
        _Arrs::AbstractArray...;
        kwargs...)
    Arrs = (A, _Arrs...)
    idcs = collect(chunks(A; n = scheduler.nchunks))
    reduction_f = append!!
    v = tmapreduce(reduction_f, idcs; scheduler, kwargs...) do inds
        args = map(A -> @view(A[inds]), Arrs)
        map(f, args...)
    end
    reshape(v, size(A)...)
end

@propagate_inbounds function tmap!(f,
        out,
        A::AbstractArray,
        _Arrs::AbstractArray...;
        scheduler::Scheduler = DynamicScheduler(),
        kwargs...)
    if hasfield(typeof(scheduler), :split) && scheduler.split != :batch
        error("Only `split == :batch` is supported because the parallel operation isn't commutative. (Scheduler: $scheduler)")
    end
    Arrs = (A, _Arrs...)
    @boundscheck check_all_have_same_indices((out, Arrs...))
    tforeach(eachindex(out); scheduler, kwargs...) do i
        args = map(A -> @inbounds(A[i]), Arrs)
        res = f(args...)
        out[i] = res
    end
    out
end

#-------------------------------------------------------------

function tcollect(::Type{T}, gen::Base.Generator{<:AbstractArray}; kwargs...) where {T}
    tmap(gen.f, T, gen.iter; kwargs...)
end
tcollect(gen::Base.Generator{<:AbstractArray}; kwargs...) = tmap(gen.f, gen.iter; kwargs...)

tcollect(::Type{T}, A; kwargs...) where {T} = tmap(identity, T, A; kwargs...)
tcollect(A; kwargs...) = tmap(identity, A; kwargs...)

end # module Implementation
