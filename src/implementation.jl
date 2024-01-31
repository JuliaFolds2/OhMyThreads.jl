module Implementation

import OhMyThreads: treduce, tmapreduce, treducemap, tforeach, tmap, tmap!, tcollect

using OhMyThreads: StableTasks, chunks, @spawn, @spawnat
using OhMyThreads.Tools: nthtid
using Base: @propagate_inbounds
using Base.Threads: nthreads, @threads

using BangBang: BangBang, append!!

function tmapreduce(f, op, Arrs...;
    nchunks::Int=nthreads(),
    split::Symbol=:batch,
    schedule::Symbol=:dynamic,
    outputtype::Type=Any,
    mapreduce_kwargs...)
    if schedule === :dynamic 
        _tmapreduce(f, op, Arrs, outputtype, nchunks, split, :default, mapreduce_kwargs)
    elseif schedule === :interactive
        _tmapreduce(f, op, Arrs, outputtype, nchunks, split, :interactive, mapreduce_kwargs)
    elseif schedule === :greedy
        _tmapreduce_greedy(f, op, Arrs, outputtype, nchunks, split, mapreduce_kwargs)
    elseif schedule === :static
        _tmapreduce_static(f, op, Arrs, outputtype, nchunks, split, mapreduce_kwargs)
    else
        schedule_err(schedule)
    end
end
@noinline schedule_err(s) = error(ArgumentError("Invalid schedule option: $s, expected :dynamic, :interactive, :greedy, or :static."))

treducemap(op, f, A...; kwargs...) = tmapreduce(f, op, A...; kwargs...)

function _tmapreduce(f, op, Arrs, ::Type{OutputType}, nchunks, split, threadpool, mapreduce_kwargs)::OutputType where {OutputType}
    check_all_have_same_indices(Arrs)
    tasks = map(chunks(first(Arrs); n=nchunks, split)) do inds
        args = map(A -> A[inds], Arrs)
        @spawn threadpool mapreduce(f, op, args...; $mapreduce_kwargs...)
    end
    mapreduce(fetch, op, tasks)
end

function _tmapreduce_greedy(f, op, Arrs, ::Type{OutputType}, nchunks, split, mapreduce_kwargs)::OutputType where {OutputType}
    nchunks > 0 || throw("Error: nchunks must be a positive integer")
    if Base.IteratorSize(first(Arrs)) isa Base.SizeUnknown
        ntasks = nchunks
    else
        check_all_have_same_indices(Arrs)
        ntasks = min(length(first(Arrs)), nchunks)
    end
    ch = Channel{Tuple{eltype.(Arrs)...}}(0; spawn=true) do ch
        for args ∈ zip(Arrs...)
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

function _tmapreduce_static(f, op, Arrs, ::Type{OutputType}, nchunks, split, mapreduce_kwargs) where {OutputType}
    check_all_have_same_indices(Arrs)
    nchunks > 0 || throw("Error: nchunks must be a positive integer")
    n = min(nthreads(), nchunks) # We could implement strategies, like round-robin, in the future
    tasks = map(enumerate(chunks(first(Arrs); n, split))) do (c, inds)
        tid = @inbounds nthtid(c)
        args = map(A -> A[inds], Arrs)
        @spawnat tid mapreduce(f, op, args...; mapreduce_kwargs...)
    end
    mapreduce(fetch, op, tasks)
end


check_all_have_same_indices(Arrs) = let A = first(Arrs), Arrs = Arrs[2:end]
    if !all(B -> eachindex(A) == eachindex(B), Arrs)
        error("The indices of the input arrays must match the indices of the output array.")
    end
end 

#-------------------------------------------------------------

function treduce(op, A...; kwargs...)
    tmapreduce(identity, op, A...; kwargs...)
end

#-------------------------------------------------------------

function tforeach(f, A...; kwargs...)::Nothing
    tmapreduce(f, (l, r) -> l, A...; kwargs..., init=nothing, outputtype=Nothing)
end

#-------------------------------------------------------------

function tmap(f, ::Type{T}, A::AbstractArray, _Arrs::AbstractArray...; kwargs...) where {T}
    Arrs = (A, _Arrs...)
    tmap!(f, similar(A, T), Arrs...; kwargs...)
end

function tmap(f, A::AbstractArray, _Arrs::AbstractArray...; nchunks::Int=nthreads(), schedule=:dynamic, kwargs...)
    Arrs = (A, _Arrs...)
    check_all_have_same_indices(Arrs)
    the_chunks = collect(chunks(A; n=nchunks))
    if schedule == :greedy
        error("Greedy schedules are not supported with `tmap` unless you provide an `OutputElementType` argument, since the greedy schedule requires a commutative reducing operator.")
    end
    # It's vital that we force split=:batch here because we're not doing a commutative operation!
    v = tmapreduce(append!!, the_chunks; kwargs...,  nchunks, split=:batch) do inds
        args = map(A -> @view(A[inds]), Arrs)
        map(f, args...)
    end
    reshape(v, size(A)...)
end

@propagate_inbounds function tmap!(f, out, A::AbstractArray, _Arrs::AbstractArray...; kwargs...)
    Arrs = (A, _Arrs...)
    @boundscheck check_all_have_same_indices((out, Arrs...))
    # It's vital that we force split=:batch here because we're not doing a commutative operation!
    tforeach(eachindex(out); kwargs..., split=:batch) do i
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
