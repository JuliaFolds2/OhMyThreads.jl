module Implementation

import OhMyThreads: treduce, tmapreduce, treducemap, tforeach, tmap, tmap!, tcollect

using OhMyThreads: StableTasks, chunks, @spawn, @spawnat
using OhMyThreads.Tools: nthtid
using Base: @propagate_inbounds
using Base.Threads: nthreads, @threads

using BangBang: BangBang, append!!

function tmapreduce(f, op, A;
    nchunks::Int=nthreads(),
    split::Symbol=:batch,
    schedule::Symbol=:dynamic,
    outputtype::Type=Any,
    kwargs...)
    if schedule === :dynamic
        _tmapreduce(f, op, A, outputtype, nchunks, split; kwargs...)
    elseif schedule === :static
        _tmapreduce_static(f, op, A, outputtype, nchunks, split; kwargs...)
    else
        schedule_err(schedule)
    end
end
@noinline schedule_err(s) = error(ArgumentError("Invalid schedule option: $s, expected :dynamic or :static."))

treducemap(op, f, A; kwargs...) = tmapreduce(f, op, A; kwargs...)

function _tmapreduce(f, op, A, ::Type{OutputType}, nchunks, split=:batch; kwargs...)::OutputType where {OutputType}
    tasks = map(chunks(A; n=nchunks, split)) do inds
        @spawn mapreduce(f, op, @view(A[inds]); kwargs...)
    end
    mapreduce(fetch, op, tasks)
end

function _tmapreduce_static(f, op, A, ::Type{OutputType}, nchunks, split; kwargs...) where {OutputType}
    nt = nthreads()
    if nchunks > nt
        # We could implement strategies, like round-robin, in the future
        throw(ArgumentError("We currently only support `nchunks <= nthreads()` for static scheduling."))
    end
    tasks = map(enumerate(chunks(A; n=nchunks, split))) do (c, inds)
        tid = @inbounds nthtid(c)
        @spawnat tid mapreduce(f, op, @view(A[inds]); kwargs...)
    end
    mapreduce(fetch, op, tasks)
end

#-------------------------------------------------------------

function treduce(op, A; kwargs...)
    tmapreduce(identity, op, A; kwargs...)
end

#-------------------------------------------------------------

function tforeach(f, A::AbstractArray; kwargs...)::Nothing
    tmapreduce(f, (l, r) -> l, A; kwargs..., init=nothing, outputtype=Nothing)
end

#-------------------------------------------------------------

function tmap(f, ::Type{T}, A::AbstractArray; kwargs...) where {T}
    tmap!(f, similar(A, T), A; kwargs...)
end

function tmap(f, A; nchunks::Int= 2*nthreads(), kwargs...)
    the_chunks = collect(chunks(A; n=nchunks))
    # It's vital that we force split=:batch here because we're not doing a commutative operation!
    v = tmapreduce(append!!, the_chunks; kwargs...,  nchunks, split=:batch) do inds
        map(f, @view A[inds])
    end
    reshape(v, size(A)...)
end

@propagate_inbounds function tmap!(f, out, A::AbstractArray; kwargs...)
    @boundscheck eachindex(out) == eachindex(A) || error("The indices of the input array must match the indices of the output array.")
    # It's vital that we force split=:batch here because we're not doing a commutative operation!
    tforeach(eachindex(A); kwargs..., split=:batch) do i
        fAi = f(@inbounds A[i])
        out[i] = fAi
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
