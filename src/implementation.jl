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
    kwargs...)
    if schedule === :dynamic 
        _tmapreduce(f, op, Arrs, outputtype, nchunks, split, :default; kwargs...)
    elseif schedule === :interactive 
        _tmapreduce(f, op, Arrs, outputtype, nchunks, split, :interactive; kwargs...)
    elseif schedule === :static
        _tmapreduce_static(f, op, Arrs, outputtype, nchunks, split; kwargs...)
    else
        schedule_err(schedule)
    end
end
@noinline schedule_err(s) = error(ArgumentError("Invalid schedule option: $s, expected :dynamic or :static."))

treducemap(op, f, A...; kwargs...) = tmapreduce(f, op, A...; kwargs...)

function _tmapreduce(f, op, Arrs, ::Type{OutputType}, nchunks, split, schedule; kwargs...)::OutputType where {OutputType}
    check_all_have_same_indices(Arrs)
    tasks = map(chunks(first(Arrs); n=nchunks, split)) do inds
        args = map(A -> A[inds], Arrs)
        @spawn schedule mapreduce(f, op, args...; kwargs...)
    end
    mapreduce(fetch, op, tasks)
end

function _tmapreduce_static(f, op, Arrs, ::Type{OutputType}, nchunks, split; kwargs...) where {OutputType}
    nt = nthreads()
    check_all_have_same_indices(Arrs)
    if nchunks > nt
        # We could implement strategies, like round-robin, in the future
        throw(ArgumentError("We currently only support `nchunks <= nthreads()` for static scheduling."))
    end
    tasks = map(enumerate(chunks(first(Arrs); n=nchunks, split))) do (c, inds)
        tid = @inbounds nthtid(c)
        args = map(A -> A[inds], Arrs)
        @spawnat tid mapreduce(f, op, args...; kwargs...)
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

function tmap(f, A::AbstractArray, _Arrs::AbstractArray...; nchunks::Int=nthreads(), kwargs...)
    Arrs = (A, _Arrs...)
    check_all_have_same_indices(Arrs)
    the_chunks = collect(chunks(A; n=nchunks))
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
