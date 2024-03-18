module Implementation

import OhMyThreads: treduce, tmapreduce, treducemap, tforeach, tmap, tmap!, tcollect
using OhMyThreads: chunks, @spawn, @spawnat, WithTaskLocals, promise_task_local
using OhMyThreads.Tools: nthtid
using OhMyThreads: Scheduler,
                   DynamicScheduler, StaticScheduler, GreedyScheduler,
                   SerialScheduler
using OhMyThreads.Schedulers: chunking_enabled,
                              chunking_mode, ChunkingMode, NoChunking,
                              FixedSize, FixedCount, scheduler_from_symbol, NotGiven,
                              isgiven
using Base: @propagate_inbounds
using Base.Threads: nthreads, @threads
using BangBang: append!!
using ChunkSplitters: ChunkSplitters

const MaybeScheduler = Union{NotGiven, Scheduler, Symbol}

include("macro_impl.jl")

function auto_disable_chunking_warning()
    @warn("You passed in a `ChunkSplitters.Chunk` but also a scheduler that has "*
          "chunking enabled. Will turn off internal chunking to proceed.\n"*
          "To avoid this warning, try to turn off chunking (`nchunks=0` and `chunksize=0`) "*
          "or pass in `collect(chunks(...))`.")
end

function _chunks(sched, arg)
    C = chunking_mode(sched)
    @assert C != NoChunking
    if C == FixedCount
        chunks(arg;
            n = sched.nchunks,
            split = sched.split)::ChunkSplitters.Chunk{
            typeof(arg), ChunkSplitters.FixedCount}
    elseif C == FixedSize
        chunks(arg;
            size = sched.chunksize,
            split = sched.split)::ChunkSplitters.Chunk{
            typeof(arg), ChunkSplitters.FixedSize}
    end
end

function _scheduler_from_userinput(scheduler::MaybeScheduler; kwargs...)
    if scheduler isa Scheduler
        isempty(kwargs) || scheduler_and_kwargs_err(; kwargs...)
        _scheduler = scheduler
    elseif scheduler isa Symbol
        _scheduler = scheduler_from_symbol(scheduler; kwargs...)
    else # default fallback
        _scheduler = DynamicScheduler(; kwargs...)
    end
end

function tmapreduce(f, op, Arrs...;
        scheduler::MaybeScheduler = NotGiven(),
        outputtype::Type = Any,
        init = NotGiven(),
        kwargs...)
    mapreduce_kwargs = isgiven(init) ? (; init) : (;)
    _scheduler = _scheduler_from_userinput(scheduler; kwargs...)
    if isempty(first(Arrs))
        isempty(mapreduce_kwargs) && reduce_empty_err()
        return mapreduce_kwargs.init
    end

    # @show _scheduler
    if _scheduler isa SerialScheduler
        mapreduce(f, op, Arrs...; mapreduce_kwargs...)
    else
        @noinline _tmapreduce(f, op, Arrs, outputtype, _scheduler, mapreduce_kwargs)
    end
end

@noinline function scheduler_and_kwargs_err(; kwargs...)
    kwargstr = join(string.(keys(kwargs)), ", ")
    throw(ArgumentError("Providing an explicit scheduler as well as direct keyword arguments (e.g. $(kwargstr)) is currently not supported."))
end

@noinline function reduce_empty_err()
    throw(ArgumentError("reducing over an empty collection is not allowed; consider supplying `init`"))
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
            # Note, calling `promise_task_local` here is only safe because we're assuming that
            # Base.mapreduce isn't going to magically try to do multithreading on us...
            @spawn threadpool mapreduce(promise_task_local(f), promise_task_local(op),
                args...; $mapreduce_kwargs...)
        end
        mapreduce(fetch, promise_task_local(op), tasks)
    else
        tasks = map(eachindex(first(Arrs))) do i
            args = map(A -> @inbounds(A[i]), Arrs)
            @spawn threadpool promise_task_local(f)(args...)
        end
        mapreduce(fetch, promise_task_local(op), tasks; mapreduce_kwargs...)
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
        @spawn threadpool promise_task_local(f)(idcs)
    end
    mapreduce(fetch, promise_task_local(op), tasks; mapreduce_kwargs...)
end

# StaticScheduler: AbstractArray/Generic
function _tmapreduce(f,
        op,
        Arrs,
        ::Type{OutputType},
        scheduler::StaticScheduler,
        mapreduce_kwargs)::OutputType where {OutputType}
    nt = nthreads()
    check_all_have_same_indices(Arrs)
    if chunking_enabled(scheduler)
        tasks = map(enumerate(_chunks(scheduler, first(Arrs)))) do (c, inds)
            tid = @inbounds nthtid(mod1(c, nt))
            args = map(A -> view(A, inds), Arrs)
            # Note, calling `promise_task_local` here is only safe because we're assuming that
            # Base.mapreduce isn't going to magically try to do multithreading on us...
            @spawnat tid mapreduce(promise_task_local(f), promise_task_local(op), args...;
                mapreduce_kwargs...)
        end
        # Note, calling `promise_task_local` here is only safe because we're assuming that
        # Base.mapreduce isn't going to magically try to do multithreading on us...
        mapreduce(fetch, promise_task_local(op), tasks)
    else
        tasks = map(enumerate(eachindex(first(Arrs)))) do (c, i)
            tid = @inbounds nthtid(mod1(c, nt))
            args = map(A -> @inbounds(A[i]), Arrs)
            @spawnat tid promise_task_local(f)(args...)
        end
        # Note, calling `promise_task_local` here is only safe because we're assuming that
        # Base.mapreduce isn't going to magically try to do multithreading on us...
        mapreduce(fetch, promise_task_local(op), tasks; mapreduce_kwargs...)
    end
end

# StaticScheduler: ChunkSplitters.Chunk
function _tmapreduce(f,
        op,
        Arrs::Tuple{ChunkSplitters.Chunk{T}}, # we don't support multiple chunks for now
        ::Type{OutputType},
        scheduler::StaticScheduler,
        mapreduce_kwargs)::OutputType where {OutputType, T}
    chunking_enabled(scheduler) && auto_disable_chunking_warning()
    check_all_have_same_indices(Arrs)
    chnks = only(Arrs)
    nt = nthreads()
    tasks = map(enumerate(chnks)) do (c, idcs)
        tid = @inbounds nthtid(mod1(c, nt))
        # Note, calling `promise_task_local` here is only safe because we're assuming that
        # Base.mapreduce isn't going to magically try to do multithreading on us...
        @spawnat tid promise_task_local(f)(idcs)
    end
    # Note, calling `promise_task_local` here is only safe because we're assuming that
    # Base.mapreduce isn't going to magically try to do multithreading on us...
    mapreduce(fetch, promise_task_local(op), tasks; mapreduce_kwargs...)
end

# NOTE: once v1.12 releases we should switch this to wait(t; throw=false)
wait_nothrow(t) = Base._wait(t)

# GreedyScheduler w/o chunking
function _tmapreduce(f,
        op,
        Arrs,
        ::Type{OutputType},
        scheduler::GreedyScheduler{NoChunking},
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
        # Note, calling `promise_task_local` here is only safe because we're assuming that
        # Base.mapreduce isn't going to magically try to do multithreading on us...
        @spawn mapreduce(promise_task_local(op), ch; mapreduce_kwargs...) do args
            promise_task_local(f)(args...)
        end
    end
    # Doing this because of https://github.com/JuliaFolds2/OhMyThreads.jl/issues/82
    # The idea is that if the channel gets fully consumed before a task gets started up,
    # then if the user does not supply an `init` kwarg, we'll get an error.
    # Current way of dealing with this is just filtering out `mapreduce_empty` method
    # errors. This may not be the most stable way of dealing with things, e.g. if the
    # name of the function throwing the error changes this could break, so long term
    # we may want to try a different design.
    filtered_tasks = filter(tasks) do stabletask
        task = stabletask.t
        istaskdone(task) || wait_nothrow(task)
        if task.result isa MethodError && task.result.f == Base.mapreduce_empty
            false
        else
            true
        end
    end
    # Note, calling `promise_task_local` here is only safe because we're assuming that
    # Base.mapreduce isn't going to magically try to do multithreading on us...
    mapreduce(fetch, promise_task_local(op), filtered_tasks; mapreduce_kwargs...)
end

# GreedyScheduler w/ chunking
function _tmapreduce(f,
        op,
        Arrs,
        ::Type{OutputType},
        scheduler::GreedyScheduler,
        mapreduce_kwargs)::OutputType where {OutputType}
    if Base.IteratorSize(first(Arrs)) isa Base.SizeUnknown
        throw(ArgumentError("SizeUnkown iterators in combination with a greedy scheduler and chunking are currently not supported."))
    end
    check_all_have_same_indices(Arrs)
    chnks = _chunks(scheduler, first(Arrs))
    ntasks_desired = scheduler.ntasks
    ntasks = min(length(chnks), ntasks_desired)

    ch = Channel{typeof(first(chnks))}(length(chnks); spawn = true) do ch
        for args in chnks
            put!(ch, args)
        end
    end
    tasks = map(1:ntasks) do _
        # Note, calling `promise_task_local` here is only safe because we're assuming that
        # Base.mapreduce isn't going to magically try to do multithreading on us...
        @spawn mapreduce(promise_task_local(op), ch; mapreduce_kwargs...) do inds
            args = map(A -> view(A, inds), Arrs)
            mapreduce(promise_task_local(f), promise_task_local(op), args...)
        end
    end
    # Doing this because of https://github.com/JuliaFolds2/OhMyThreads.jl/issues/82
    # The idea is that if the channel gets fully consumed before a task gets started up,
    # then if the user does not supply an `init` kwarg, we'll get an error.
    # Current way of dealing with this is just filtering out `mapreduce_empty` method
    # errors. This may not be the most stable way of dealing with things, e.g. if the
    # name of the function throwing the error changes this could break, so long term
    # we may want to try a different design.
    filtered_tasks = filter(tasks) do stabletask
        task = stabletask.t
        istaskdone(task) || wait_nothrow(task)
        if task.result isa MethodError && task.result.f == Base.mapreduce_empty
            false
        else
            true
        end
    end
    # Note, calling `promise_task_local` here is only safe because we're assuming that
    # Base.mapreduce isn't going to magically try to do multithreading on us...
    mapreduce(fetch, promise_task_local(op), filtered_tasks; mapreduce_kwargs...)
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

function maybe_rewrap(g::G, f::F) where {G, F}
    g(f)
end

"""
   maybe_rewrap(g, f)

takes a closure `g(f)` and if `f` is a `WithTaskLocals`, we're going
to unwrap `f` and delegate its `TaskLocalValues` to `g`.

This should always be equivalent to just calling `g(f)`.
"""
function maybe_rewrap(g::G, f::WithTaskLocals{F}) where {G, F}
    (; inner_func, tasklocals) = f
    WithTaskLocals(vals -> g(inner_func(vals)), tasklocals)
end

#------------------------------------------------------------

function tmap(f, ::Type{T}, A::AbstractArray, _Arrs::AbstractArray...; kwargs...) where {T}
    Arrs = (A, _Arrs...)
    tmap!(f, similar(A, T), Arrs...; kwargs...)
end

function tmap(f,
        A::Union{AbstractArray, ChunkSplitters.Chunk},
        _Arrs::AbstractArray...;
        scheduler::MaybeScheduler = NotGiven(),
        kwargs...)
    _scheduler = _scheduler_from_userinput(scheduler; kwargs...)

    if _scheduler isa GreedyScheduler
        error("Greedy scheduler isn't supported with `tmap` unless you provide an `OutputElementType` argument, since the greedy schedule requires a commutative reducing operator.")
    end
    if chunking_enabled(_scheduler) && hasfield(typeof(_scheduler), :split) &&
       _scheduler.split != :batch
        error("Only `split == :batch` is supported because the parallel operation isn't commutative. (Scheduler: $_scheduler)")
    end
    if A isa ChunkSplitters.Chunk && chunking_enabled(_scheduler)
        auto_disable_chunking_warning()
        if _scheduler isa DynamicScheduler
            _scheduler = DynamicScheduler(;
                threadpool = _scheduler.threadpool,
                chunking = false)
        elseif _scheduler isa StaticScheduler
            _scheduler = StaticScheduler(; chunking = false)
        else
            error("Can't disable chunking for this scheduler?! Shouldn't be reached.",
                _scheduler)
        end
    end

    Arrs = (A, _Arrs...)
    if _scheduler isa SerialScheduler
        map(f, Arrs...; kwargs...)
    else
        check_all_have_same_indices(Arrs)
        @noinline _tmap(_scheduler, f, A, _Arrs...)
    end
end

# w/o chunking (DynamicScheduler{NoChunking}): AbstractArray
function _tmap(scheduler::DynamicScheduler{NoChunking},
        f,
        A::AbstractArray,
        _Arrs::AbstractArray...;)
    (; threadpool) = scheduler
    Arrs = (A, _Arrs...)
    tasks = map(eachindex(A)) do i
        @spawn threadpool begin
            args = map(A -> A[i], Arrs)
            promise_task_local(f)(args...)
        end
    end
    v = map(fetch, tasks)
    reshape(v, size(A)...)
end

# w/o chunking (DynamicScheduler{NoChunking}): ChunkSplitters.Chunk
function _tmap(scheduler::DynamicScheduler{NoChunking},
        f,
        A::ChunkSplitters.Chunk,
        _Arrs::AbstractArray...)
    (; threadpool) = scheduler
    tasks = map(A) do idcs
        @spawn threadpool promise_task_local(f)(idcs)
    end
    map(fetch, tasks)
end

# w/o chunking (StaticScheduler{NoChunking}): ChunkSplitters.Chunk
function _tmap(scheduler::StaticScheduler{NoChunking},
        f,
        A::ChunkSplitters.Chunk,
        _Arrs::AbstractArray...)
    nt = nthreads()
    tasks = map(enumerate(A)) do (c, idcs)
        tid = @inbounds nthtid(mod1(c, nt))
        @spawnat tid promise_task_local(f)(idcs)
    end
    map(fetch, tasks)
end

# w/o chunking (StaticScheduler{NoChunking}): AbstractArray
function _tmap(scheduler::StaticScheduler{NoChunking},
        f,
        A::AbstractArray,
        _Arrs::AbstractArray...;)
    Arrs = (A, _Arrs...)
    nt = nthreads()
    tasks = map(enumerate(A)) do (c, i)
        tid = @inbounds nthtid(mod1(c, nt))
        @spawnat tid begin
            args = map(A -> A[i], Arrs)
            promise_task_local(f)(args...)
        end
    end
    v = map(fetch, tasks)
    reshape(v, size(A)...)
end

# w/ chunking
function _tmap(scheduler::Scheduler,
        f,
        A::AbstractArray,
        _Arrs::AbstractArray...)
    Arrs = (A, _Arrs...)
    idcs = collect(_chunks(scheduler, A))
    reduction_f = append!!
    mapping_f = maybe_rewrap(f) do f
        (inds) -> begin
            args = map(A -> @view(A[inds]), Arrs)
            map(f, args...)
        end
    end
    v = tmapreduce(mapping_f, reduction_f, idcs; scheduler)
    reshape(v, size(A)...)
end

@propagate_inbounds function tmap!(f,
        out,
        A::AbstractArray,
        _Arrs::AbstractArray...;
        scheduler::MaybeScheduler = NotGiven(),
        kwargs...)
    _scheduler = _scheduler_from_userinput(scheduler; kwargs...)

    Arrs = (A, _Arrs...)
    if _scheduler isa SerialScheduler
        map!(f, out, Arrs...)
    else
        @boundscheck check_all_have_same_indices((out, Arrs...))
        mapping_f = maybe_rewrap(f) do f
            function mapping_function(i)
                args = map(A -> @inbounds(A[i]), Arrs)
                res = f(args...)
                out[i] = res
            end
        end
        @noinline tforeach(mapping_f, eachindex(out); scheduler = _scheduler)
        out
    end
end

#-------------------------------------------------------------

function tcollect(::Type{T}, gen::Base.Generator{<:AbstractArray}; kwargs...) where {T}
    tmap(gen.f, T, gen.iter; kwargs...)
end
tcollect(gen::Base.Generator{<:AbstractArray}; kwargs...) = tmap(gen.f, gen.iter; kwargs...)

tcollect(::Type{T}, A; kwargs...) where {T} = tmap(identity, T, A; kwargs...)
tcollect(A; kwargs...) = tmap(identity, A; kwargs...)

end # module Implementation
