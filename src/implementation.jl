module Implementation

import OhMyThreads: treduce, tmapreduce, treducemap, tforeach, tmap, tmap!, tcollect

using OhMyThreads: chunks, @spawn, @spawnat
using OhMyThreads.Tools: nthtid
using OhMyThreads: Scheduler, DynamicScheduler, StaticScheduler, GreedyScheduler
using OhMyThreads.Schedulers: chunking_enabled, chunking_mode, ChunkingMode, NoChunking,
                              FixedSize, FixedCount
using Base: @propagate_inbounds
using Base.Threads: nthreads, @threads

using BangBang: append!!

using ChunkSplitters: ChunkSplitters

include("macro_impl.jl")

function auto_disable_chunking_warning()
    @warn("You passed in a `ChunkSplitters.Chunk` but also a scheduler that has "*
          "chunking enabled. Will turn off internal chunking to proceed.\n"*
          "To avoid this warning, try to turn off chunking (`nchunks=0` and `chunksize=0`) "*
          "or pass in `collect(chunks(...))`.")
end

function _chunks(sched, arg; kwargs...)
    C = chunking_mode(sched)
    @assert C != NoChunking
    if C == FixedCount
        chunks(arg; n = sched.nchunks, split = sched.split, kwargs...)
    elseif C == FixedSize
        chunks(arg; size = sched.chunksize, split = sched.split, kwargs...)
    end
end

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
    (; threadpool) = scheduler
    check_all_have_same_indices(Arrs)
    if chunking_enabled(scheduler)
        tasks = map(_chunks(scheduler, first(Arrs))) do inds
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
        Arrs::Tuple{ChunkSplitters.Chunk{T}}, # we don't support multiple chunks for now
        ::Type{OutputType},
        scheduler::DynamicScheduler,
        mapreduce_kwargs)::OutputType where {OutputType, T}
    (; nchunks, split, threadpool) = scheduler
    chunking_enabled(scheduler) && auto_disable_chunking_warning()
    tasks = map(only(Arrs)) do idcs
        @spawn threadpool f(idcs)
    end
    mapreduce(fetch, op, tasks; mapreduce_kwargs...)
end

# StaticScheduler: AbstractArray/Generic
function _tmapreduce(f,
        op,
        Arrs,
        ::Type{OutputType},
        scheduler::StaticScheduler,
        mapreduce_kwargs) where {OutputType}
    check_all_have_same_indices(Arrs)
    if chunking_enabled(scheduler)
        n = min(nthreads(), scheduler.nchunks) # We could implement strategies, like round-robin, in the future
        # tasks = map(enumerate(chunks(first(Arrs); n, split))) do (c, inds)
        tasks = map(enumerate(_chunks(scheduler, first(Arrs); n))) do (c, inds)
            tid = @inbounds nthtid(c)
            args = map(A -> view(A, inds), Arrs)
            @spawnat tid mapreduce(f, op, args...; mapreduce_kwargs...)
        end
        mapreduce(fetch, op, tasks)
    else
        if length(first(Arrs)) > nthreads()
            error("You have disabled chunking but provided an input with more then " *
                  "`nthreads()` elements. This is not supported for `StaticScheduler`.")
        end
        n = min(nthreads(), nchunks) # We could implement strategies, like round-robin, in the future
        tasks = map(enumerate(eachindex(first(Arrs)))) do (c, i)
            tid = @inbounds nthtid(c)
            args = map(A -> @inbounds(A[i]), Arrs)
            @spawnat tid f(args...)
        end
        mapreduce(fetch, op, tasks; mapreduce_kwargs...)
    end
end

# StaticScheduler: ChunkSplitters.Chunk
function _tmapreduce(f,
        op,
        Arrs::Tuple{ChunkSplitters.Chunk{T}}, # we don't support multiple chunks for now
        ::Type{OutputType},
        scheduler::StaticScheduler,
        mapreduce_kwargs) where {OutputType, T}
    chunking_enabled(scheduler) && auto_disable_chunking_warning()
    check_all_have_same_indices(Arrs)
    chnks = only(Arrs)
    if length(chnks) > nthreads()
        error("You provided a `ChunkSplitters.Chunk` with more than `nthreads()` chunks " *
              "as input, which is not supported by the `StaticScheduler`.")
    end
    tasks = map(enumerate(chnks)) do (c, idcs)
        tid = @inbounds nthtid(c)
        @spawnat tid f(idcs)
    end
    mapreduce(fetch, op, tasks; mapreduce_kwargs...)
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
    if A isa ChunkSplitters.Chunk && chunking_enabled(scheduler)
        auto_disable_chunking_warning()
        if scheduler isa DynamicScheduler
            scheduler = DynamicScheduler(; nchunks = 0, scheduler.threadpool)
        elseif scheduler isa StaticScheduler
            scheduler = StaticScheduler(; nchunks = 0)
        else
            error("Can't disable chunking for this scheduler?! Shouldn't be reached.",
                scheduler)
        end
    end

    Arrs = (A, _Arrs...)
    check_all_have_same_indices(Arrs)
    _tmap(scheduler, f, A, _Arrs...; kwargs...)
end

# w/o chunking (DynamicScheduler{NoChunking}): AbstractArray
function _tmap(scheduler::DynamicScheduler{NoChunking},
        f,
        A::AbstractArray,
        _Arrs::AbstractArray...;
        kwargs...)
    (; threadpool) = scheduler
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

# w/o chunking (DynamicScheduler{NoChunking}): ChunkSplitters.Chunk
function _tmap(scheduler::DynamicScheduler{NoChunking},
        f,
        A::ChunkSplitters.Chunk,
        _Arrs::AbstractArray...;
        kwargs...)
    (; threadpool) = scheduler
    tasks = map(A) do idcs
        @spawn threadpool f(idcs)
    end
    map(fetch, tasks)
end

# w/o chunking (StaticScheduler{NoChunking}): ChunkSplitters.Chunk
function _tmap(scheduler::StaticScheduler{NoChunking},
        f,
        A::ChunkSplitters.Chunk,
        _Arrs::AbstractArray...;
        kwargs...)
    if length(A) > nthreads()
        error("You provided a `ChunkSplitters.Chunk` with more than `nthreads()` chunks " *
              "as input, which is not supported by the `StaticScheduler`.")
    end
    tasks = map(enumerate(A)) do (c, idcs)
        tid = @inbounds nthtid(c)
        @spawnat tid f(idcs)
    end
    map(fetch, tasks)
end

# w/ chunking
function _tmap(scheduler::Scheduler,
        f,
        A::AbstractArray,
        _Arrs::AbstractArray...;
        kwargs...)
    Arrs = (A, _Arrs...)
    idcs = collect(_chunks(scheduler, A))
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
