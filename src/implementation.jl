module Implementation

import ThreadsBasics: treduce, tmapreduce, treducemap, tforeach, tmap, tmap!

using ThreadsBasics: chunks, @spawn
using Base: @propagate_inbounds
using Base.Threads: nthreads, @threads

using BangBang: append!!

function tmapreduce(f, op, A;
                    nchunks::Int = 2 * nthreads(),
                    split::Symbol = :batch,
                    schedule::Symbol =:dynamic,
                    outputtype::Type = Any,
                    kwargs...)
    if schedule === :dynamic
        _tmapreduce(f, op, A, outputtype, nchunks, split; kwargs...)
    elseif schedule === :static
        _tmapreduce_static(f, op, outputtype, A, nchunks, split; kwargs...)
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

function _tmapreduce_static(f, op, ::Type{OutputType}, A, nchunks, split; kwargs...) where {OutputType}
    results = Vector{OutputType}(undef, min(nchunks, length(A)))
    @threads :static for (ichunk, inds) ∈ enumerate(chunks(A; n=nchunks, split))
        results[ichunk] = mapreduce(f, op, @view(A[inds]); kwargs...)
    end
    reduce(op, results; kwargs...)
end

#-------------------------------------------------------------

function treduce(op, A; kwargs...)
    tmapreduce(identity, op, A; kwargs...)
end

#-------------------------------------------------------------

function tforeach(f, A::AbstractArray; kwargs...)::Nothing
    tmapreduce(f, (l, r)->l, A; kwargs..., init=nothing, outputtype=Nothing)
end

#-------------------------------------------------------------

function tmap(f, ::Type{T}, A::AbstractArray; kwargs...) where {T}
    tmap!(f, similar(A, T), A; kwargs...)
end

function tmap(f, A; nchunks::Int= 2*nthreads(), kwargs...)
    the_chunks = collect(chunks(A; n=nchunks))
    v = tmapreduce(append!!, the_chunks; kwargs...,  nchunks, split=:batch) do inds
        map(f, @view A[inds])
    end
    reshape(v, size(A)...)
end


@propagate_inbounds function tmap!(f, out, A::AbstractArray; kwargs...)
    @boundscheck eachindex(out) == eachindex(A) ||
        error("The indices of the input array must match the indices of the output array.")
    tforeach(eachindex(A); kwargs...) do i
        fAi = f(@inbounds A[i])
        out[i] = fAi 
    end
    out
end


end # module Implementation
