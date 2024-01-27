module ThreadsBasics

using Base: @propagate_inbounds
using Base.Threads: nthreads
using StableTasks: @spawn
using SplittablesBase: amount, halve

export treduce, tmapreduce, treducemap, tmap, tmap!, tforeach

struct NoInit end

"""
    tmapreduce(f, op, itr; [init]
               chunks_per_thread::Int = 2,
               chunk_size = max(1, amount(itr) ÷ (chunks_per_thread * nthreads())))

A multithreaded function like `Base.mapreduce`. Perform a reduction over `itr`, applying a single-argument
function `f` to each element, and then combining them with the two-argument function `op`. `op` **must** be an
[associative](https://en.wikipedia.org/wiki/Associative_property) function, in the sense that
`op(a, op(b, c)) ≈ op(op(a, b), c)`. If `op` is not (approximately) associative, you will get undefined
results.

For a very well known example of `mapreduce`, `sum(f, itr)` is equivalent to `mapreduce(f, +, itr)`. Doing

     treducemap(+, √, [1, 2, 3, 4, 5])

is the parallelized version of

     (√1 + √2) + (√3 + √4) + √5

This reduction is tree-based.

## Keyword arguments:

- Uses can provide *either* `chunk_size`, or `chunks_per_thread` (and if both are provided, `chunk_size` is used)
    - `chunks_per_thread` (defaults `2`), will try to split up `itr` so that each thread will recieve *approximately* `chunks_per_thread` pieces of data to work on. More `chunks_per_thread`, typically means better [load balancing](https://en.wikipedia.org/wiki/Load_balancing_(computing)).
    - `chunk_size` (computed based on `chunks_per_thread` by deault). Data from `itr` will be divided in half using `halve` from [SplittablesBase.jl](https://github.com/JuliaFolds2/SplittablesBase.jl) until those chunks have an `SplittablesBase.amount` less than or equal to `chunk_size`. The chunks are then operated on in sequential with `mapreduce(f, op, chunk; [init])`, and then the chunks are combined using `op`.
- `init` optional keyword argument forwarded to `reduce` for the sequential parts of the calculation.
"""
function tmapreduce(f, op, itr;
                    init=NoInit(),
                    chunks_per_thread::Int = 2,
                    chunk_size = max(1, amount(itr) ÷ (chunks_per_thread * nthreads())))
    _tmapreduce(f, op, itr; init, chunk_size)
end

"""
    treducemap(op, f, itr; [init]
               chunks_per_thread::Int = 2,
               chunk_size = max(1, amount(itr) ÷ (chunks_per_thread * nthreads())))

Like `tmapreduce` except the order of the `f` and `op` arguments are switched. Perform a reduction over `itr`,
applying a single-argument function `f` to each element, and then combining them with the two-argument
function `op`. `op` **must** be an [associative](https://en.wikipedia.org/wiki/Associative_property) function,
in the sense that `op(a, op(b, c)) ≈ op(op(a, b), c)`. If `op` is not (approximately) associative, you will
get undefined results.

For a very well known example of `mapreduce`, `sum(f, itr)` is equivalent to `mapreduce(f, +, itr)`. Doing

     treducemap(+, √, [1, 2, 3, 4, 5])

is the parallelized version of

     (√1 + √2) + (√3 + √4) + √5

This reduction is tree-based.

## Keyword arguments:

- Uses can provide *either* `chunk_size`, or `chunks_per_thread` (and if both are provided, `chunk_size` is used)
    - `chunks_per_thread` (defaults `2`), will try to split up `itr` so that each thread will recieve *approximately* `chunks_per_thread` pieces of data to work on. More `chunks_per_thread`, typically means better [load balancing](https://en.wikipedia.org/wiki/Load_balancing_(computing)).
    - `chunk_size` (computed based on `chunks_per_thread` by deault). Data from `itr` will be divided in half using `halve` from [SplittablesBase.jl](https://github.com/JuliaFolds2/SplittablesBase.jl) until those chunks have an `SplittablesBase.amount` less than or equal to `chunk_size`. The chunks are then operated on sequentially with `mapreduce(f, op, chunk; [init])`, and then the chunks are combined using `op`.
- `init` optional keyword argument forwarded to `mapreduce` for the sequential parts of the calculation.
"""
treducemap(op, f, itr; kwargs...) = tmapreduce(f, op, itr; kwargs...)

function _tmapreduce(f, op, itr; chunk_size::Int, init)
    if amount(itr) <= chunk_size
        kwargs = init === NoInit() ? (;) : (; init)
        mapreduce(f, op, itr; kwargs...)
    else
        l, r = halve(itr)
        # @show l, r
        # error()
        task_r = @spawn _tmapreduce(f, op, r; chunk_size, init)
        result_l = _tmapreduce(f, op, l; chunk_size, init)
        op(result_l, fetch(task_r))
    end
end

"""
    treduce(op, itr; [init]
            chunks_per_thread::Int = 2,
            chunk_size = max(1, amount(itr) ÷ (chunks_per_thread * nthreads())))

A multithreaded parallel function like `Base.reduce`. Perform a reduction over `itr`, then combining each
element with the two-argument function `op`. `op` **must** be an
[associative](https://en.wikipedia.org/wiki/Associative_property) function, in the sense that
`op(a, op(b, c)) ≈ op(op(a, b), c)`. If `op` is not (approximately) associative, you will get undefined
results.

For a very well known example of `reduce`, `sum(itr)` is equivalent to `reduce(+, itr)`. Doing

     treduce(+, [1, 2, 3, 4, 5])

is the parallelized version of

     (1 + 2) + (3 + 4) + 5

This reduction is tree-based.

## Keyword arguments:

- Uses can provide *either* `chunk_size`, or `chunks_per_thread` (and if both are provided, `chunk_size` is used)
    - `chunks_per_thread` (defaults `2`), will try to split up `itr` so that each thread will recieve *approximately* `chunks_per_thread` pieces of data to work on. More `chunks_per_thread`, typically means better [load balancing](https://en.wikipedia.org/wiki/Load_balancing_(computing)).
    - `chunk_size` (computed based on `chunks_per_thread` by deault). Data from `itr` will be divided in half using `halve` from [SplittablesBase.jl](https://github.com/JuliaFolds2/SplittablesBase.jl) until those chunks have an `SplittablesBase.amount` less than or equal to `chunk_size`. The chunks are then operated on sequentially with `reduce(op, chunk; [init])`, and then the chunks are combined using `op`.
- `init` optional keyword argument forwarded to `reduce` for the sequential parts of the calculation.
"""
function treduce(op, itr;
                 chunks_per_thread::Int = 2,
                 chunk_size = max(1, amount(itr) ÷ (chunks_per_thread * nthreads())))
    _tmapreduce(identity, op, itr; chunk_size, init)
end


"""
    tforeach(f, itr; chunks_per_thread::Int = 2,
             chunk_size = max(1, amount(itr) ÷ (chunks_per_thread * nthreads())))

Apply `f` to each element of `itr` on multiple parallel tasks, with each thread being given a number of chunks
from `itr` to work on approximately equal to `chunks_per_thread`. Instead of providing `chunks_per_thread`,
users can provide `chunk_size` directly, which means that the data will be split into chunks of at most
`chunk_size` in length.

## Keyword arguments:

- Uses can provide *either* `chunk_size`, or `chunks_per_thread` (and if both are provided, `chunk_size` is used)
    - `chunks_per_thread` (defaults `2`), will try to split up `itr` so that each thread will recieve *approximately* `chunks_per_thread` pieces of data to work on. More `chunks_per_thread`, typically means better [load balancing](https://en.wikipedia.org/wiki/Load_balancing_(computing)).
    - `chunk_size` (computed based on `chunks_per_thread` by deault). Data from `itr` will be divided in half using `halve` from [SplittablesBase.jl](https://github.com/JuliaFolds2/SplittablesBase.jl) until those chunks have an `SplittablesBase.amount` less than or equal to `chunk_size`. The chunks are then operated on in sequential with `reduce(op, chunk; [init])`, and then the chunks are combined using `op`.
"""
function tforeach(f, itr;
                  chunks_per_thread::Int = 2,
                  chunk_size = max(1, amount(itr) ÷ (chunks_per_thread * nthreads())))::Nothing
    tmapreduce(f, (l, r)->l, itr; init=nothing)
end

"""
    tmap(f, ::Type{T}, A::AbstractArray; 
         chunks_per_thread::Int = 2,
         chunk_size = max(1, amount(itr) ÷ (chunks_per_thread * nthreads()))

A multithreaded function like `Base.map`. Create a new container `similar` to `A` with eltype `T`, whose `i`th
element is equal to `f(A[i])`. This container is filled in parallel on multiple tasks.


## Keyword arguments:

- Uses can provide *either* `chunk_size`, or `chunks_per_thread` (and if both are provided, `chunk_size` is used)
    - `chunks_per_thread` (defaults `2`), will try to split up `itr` so that each thread will recieve *approximately* `chunks_per_thread` pieces of data to work on. More `chunks_per_thread`, typically means better [load balancing](https://en.wikipedia.org/wiki/Load_balancing_(computing)).
    - `chunk_size` (computed based on `chunks_per_thread` by deault). Data from `itr` will be divided in half using `halve` from [SplittablesBase.jl](https://github.com/JuliaFolds2/SplittablesBase.jl) until those chunks have an `SplittablesBase.amount` less than or equal to `chunk_size`. The chunks are then operated on sequentially.
"""
function tmap(f, ::Type{T}, A::AbstractArray; 
              chunks_per_thread::Int = 2,
              chunk_size = max(1, amount(itr) ÷ (chunks_per_thread * nthreads()))) where {T}
    tmap!(f, similar(A, T), A; chunk_size)
end


"""
    tmap!(f, out, A::AbstractArray; 
          chunks_per_thread::Int = 2,
          chunk_size = max(1, amount(itr) ÷ (chunks_per_thread * nthreads()))

A multithreaded function like `Base.map!`. In parallel on multiple tasks, this function assigns each element
of `out[i] = f(A[i])` for each index `i` of `A` and `out`.

## Keyword arguments:

- Uses can provide *either* `chunk_size`, or `chunks_per_thread` (and if both are provided, `chunk_size` is used)
    - `chunks_per_thread` (defaults `2`), will try to split up `itr` so that each thread will recieve *approximately* `chunks_per_thread` pieces of data to work on. More `chunks_per_thread`, typically means better [load balancing](https://en.wikipedia.org/wiki/Load_balancing_(computing)).
    - `chunk_size` (computed based on `chunks_per_thread` by deault). Data from `itr` will be divided in half using `halve` from [SplittablesBase.jl](https://github.com/JuliaFolds2/SplittablesBase.jl) until those chunks have an `SplittablesBase.amount` less than or equal to `chunk_size`. The chunks are then operated on sequentially.
"""
@propagate_inbounds function tmap!(f, out, A::AbstractArray; 
                                   chunks_per_thread::Int = 2,
                                   chunk_size = max(1, amount(itr) ÷ (chunks_per_thread * nthreads()))) where {T}
    @boundscheck eachindex(out) == eachindex(A) ||
        error("The indices of the input array must match the indices of the output array.")
    tforeach(eachindex(A)) do i
        fAi = f(@inbounds A[i])
        @inbounds out[i] = fAi 
    end
    out
end

end # module ThreadsBasics
