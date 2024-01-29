module OhMyThreads


using StableTasks: StableTasks, @spawn, @spawnat
using ChunkSplitters: chunks

export chunks, treduce, tmapreduce, treducemap, tmap, tmap!, tforeach, tcollect

"""
    tmapreduce(f, op, A::AbstractArray;
               [init],
               nchunks::Int = nthreads(),
               split::Symbol = :batch,
               schedule::Symbol =:dynamic,
               outputtype::Type = Any)

A multithreaded function like `Base.mapreduce`. Perform a reduction over `A`, applying a single-argument
function `f` to each element, and then combining them with the two-argument function `op`. `op` **must** be an
[associative](https://en.wikipedia.org/wiki/Associative_property) function, in the sense that
`op(a, op(b, c)) ≈ op(op(a, b), c)`. If `op` is not (approximately) associative, you will get undefined
results.

For a very well known example of `mapreduce`, `sum(f, A)` is equivalent to `mapreduce(f, +, A)`. Doing

     tmapreduce(√, +, [1, 2, 3, 4, 5])

is the parallelized version of

     (√1 + √2) + (√3 + √4) + √5

This data is divided into chunks to be worked on in parallel using [ChunkSplitters.jl](https://github.com/JuliaFolds2/ChunkSplitters.jl).

## Keyword arguments:

- `init` optional keyword argument forwarded to `mapreduce` for the sequential parts of the calculation.
- `nchunks::Int` (default `nthreads()`) is passed to `ChunkSplitters.chunks` to inform it how many pieces of data should be worked on in parallel. Greater `nchunks` typically helps with [load balancing](https://en.wikipedia.org/wiki/Load_balancing_(computing)), but at the expense of creating more overhead.
- `split::Symbol` (default `:batch`) is passed to `ChunkSplitters.chunks` to inform it if the data chunks to be worked on should be contiguous (:batch) or shuffled (:scatter). If `scatter` is chosen, then your reducing operator `op` **must** be [commutative](https://en.wikipedia.org/wiki/Commutative_property) in addition to being associative, or you could get incorrect results!
- `schedule::Symbol` either `:dynamic` or `:static` (default `:dynamic`), determines how the parallel portions of the calculation are scheduled. `:dynamic` scheduling is generally preferred since it is more flexible and better at load balancing, but `:static` scheduling can sometimes be more performant when the time it takes to complete a step of the calculation is highly uniform, and no other parallel functions are running at the same time.
- `outputtype::Type` (default `Any`) will work as the asserted output type of parallel calculations. This is typically only
needed if you are using a `:static` schedule, since the `:dynamic` schedule is uses [StableTasks.jl](https://github.com/MasonProtter/StableTasks.jl), but if you experience problems with type stability, you may be able to recover it with the `outputtype` keyword argument.
"""
function tmapreduce end

"""
    treducemap(op, f, A::AbstractArray;
               [init],
               nchunks::Int = nthreads(),
               split::Symbol = :batch,
               schedule::Symbol =:dynamic,
               outputtype::Type = Any)

Like `tmapreduce` except the order of the `f` and `op` arguments are switched. This is sometimes convenient with `do`-block notation.
Perform a reduction over `A`, applying a single-argument function `f` to each element, and then combining them with the two-argument
function `op`. `op` **must** be an [associative](https://en.wikipedia.org/wiki/Associative_property) function,
in the sense that `op(a, op(b, c)) ≈ op(op(a, b), c)`. If `op` is not (approximately) associative, you will
get undefined results.

For a very well known example of `mapreduce`, `sum(f, A)` is equivalent to `mapreduce(f, +, A)`. Doing

     treducemap(+, √, [1, 2, 3, 4, 5])

is the parallelized version of

     (√1 + √2) + (√3 + √4) + √5


This data is divided into chunks to be worked on in parallel using [ChunkSplitters.jl](https://github.com/JuliaFolds2/ChunkSplitters.jl).

## Keyword arguments:

- `init` optional keyword argument forwarded to `mapreduce` for the sequential parts of the calculation.
- `nchunks::Int` (default `nthreads()`) is passed to `ChunkSplitters.chunks` to inform it how many pieces of data should be worked on in parallel. Greater `nchunks` typically helps with [load balancing](https://en.wikipedia.org/wiki/Load_balancing_(computing)), but at the expense of creating more overhead.
- `split::Symbol` (default `:batch`) is passed to `ChunkSplitters.chunks` to inform it if the data chunks to be worked on should be contiguous (:batch) or shuffled (:scatter). If `scatter` is chosen, then your reducing operator `op` **must** be [commutative](https://en.wikipedia.org/wiki/Commutative_property) in addition to being associative, or you could get incorrect results!
- `schedule::Symbol` either `:dynamic` or `:static` (default `:dynamic`), determines how the parallel portions of the calculation are scheduled. `:dynamic` scheduling should be preferred since it is more flexible and better at load balancing, and more likely to be type stable. However, `:static` scheduling can sometimes be more performant when the time it takes to complete a step of the calculation is highly uniform, and no other parallel functions are running at the same time.
- `outputtype::Type` (default `Any`) will work as the asserted output type of parallel calculations. This is typically only
needed if you are using a `:static` schedule, since the `:dynamic` schedule is uses [StableTasks.jl](https://github.com/MasonProtter/StableTasks.jl), but if you experience problems with type stability, you may be able to recover it with the `outputtype` keyword argument.
"""
function treducemap end


"""
    treduce(op, A::AbstractArray; [init],
            nchunks::Int = nthreads(),
            split::Symbol = :batch,
            schedule::Symbol =:dynamic,
            outputtype::Type = Any)

Like `tmapreduce` except the order of the `f` and `op` arguments are switched. Perform a reduction over `A`,
applying a single-argument function `f` to each element, and then combining them with the two-argument
function `op`. `op` **must** be an [associative](https://en.wikipedia.org/wiki/Associative_property) function,
in the sense that `op(a, op(b, c)) ≈ op(op(a, b), c)`. If `op` is not (approximately) associative, you will
get undefined results.

For a very well known example of `reduce`, `sum(A)` is equivalent to `reduce(+, A)`. Doing

     treduce(+, [1, 2, 3, 4, 5])

is the parallelized version of

     (1 + 2) + (3 + 4) + 5


This data is divided into chunks to be worked on in parallel using [ChunkSplitters.jl](https://github.com/JuliaFolds2/ChunkSplitters.jl).

## Keyword arguments:

- `init` optional keyword argument forwarded to `mapreduce` for the sequential parts of the calculation.
- `nchunks::Int` (default `nthreads()`) is passed to `ChunkSplitters.chunks` to inform it how many pieces of data should be worked on in parallel. Greater `nchunks` typically helps with [load balancing](https://en.wikipedia.org/wiki/Load_balancing_(computing)), but at the expense of creating more overhead.
- `split::Symbol` (default `:batch`) is passed to `ChunkSplitters.chunks` to inform it if the data chunks to be worked on should be contiguous (:batch) or shuffled (:scatter). If `scatter` is chosen, then your reducing operator `op` **must** be [commutative](https://en.wikipedia.org/wiki/Commutative_property) in addition to being associative, or you could get incorrect results!
- `schedule::Symbol` either `:dynamic` or `:static` (default `:dynamic`), determines how the parallel portions of the calculation are scheduled. `:dynamic` scheduling is generally preferred since it is more flexible and better at load balancing, but `:static` scheduling can sometimes be more performant when the time it takes to complete a step of the calculation is highly uniform, and no other parallel functions are running at the same time.
- `outputtype::Type` (default `Any`) will work as the asserted output type of parallel calculations. This is typically only
needed if you are using a `:static` schedule, since the `:dynamic` schedule is uses [StableTasks.jl](https://github.com/MasonProtter/StableTasks.jl), but if you experience problems with type stability, you may be able to recover it with the `outputtype` keyword argument.
"""
function treduce end

"""
    tforeach(f, A::AbstractArray;
             nchunks::Int = nthreads(),
             split::Symbol = :batch,
             schedule::Symbol =:dynamic) :: Nothing

A multithreaded function like `Base.foreach`. Apply `f` to each element of `A` on multiple parallel tasks, and return `nothing`, i.e. it is the parallel equivalent of

    for x in A
        f(x)
    end

## Keyword arguments:

- `nchunks::Int` (default `nthreads()`) is passed to `ChunkSplitters.chunks` to inform it how many pieces of data should be worked on in parallel. Greater `nchunks` typically helps with [load balancing](https://en.wikipedia.org/wiki/Load_balancing_(computing)), but at the expense of creating more overhead.
- `split::Symbol` (default `:batch`) is passed to `ChunkSplitters.chunks` to inform it if the data chunks to be worked on should be contiguous (:batch) or shuffled (:scatter). If `scatter` is chosen, then your reducing operator `op` **must** be [commutative](https://en.wikipedia.org/wiki/Commutative_property) in addition to being associative, or you could get incorrect results!
- `schedule::Symbol` either `:dynamic` or `:static` (default `:dynamic`), determines how the parallel portions of the calculation are scheduled. `:dynamic` scheduling is generally preferred since it is more flexible and better at load balancing, but `:static` scheduling can sometimes be more performant when the time it takes to complete a step of the calculation is highly uniform, and no other parallel functions are running at the same time.
"""
function tforeach end

"""
    tmap(f, [OutputElementType], A::AbstractArray; 
         nchunks::Int = nthreads(),
         split::Symbol = :batch,
         schedule::Symbol =:dynamic)

A multithreaded function like `Base.map`. Create a new container `similar` to `A` whose `i`th element is
equal to `f(A[i])`. This container is filled in parallel on multiple tasks. The optional argument
`OutputElementType` will select a specific element type for the returned container, and will generally incur
fewer allocations than the version where `OutputElementType` is not specified.


## Keyword arguments:

- `nchunks::Int` (default `nthreads()`) is passed to `ChunkSplitters.chunks` to inform it how many pieces of data should be worked on in parallel. Greater `nchunks` typically helps with [load balancing](https://en.wikipedia.org/wiki/Load_balancing_(computing)), but at the expense of creating more overhead.
- `split::Symbol` (default `:batch`) is passed to `ChunkSplitters.chunks` to inform it if the data chunks to be worked on should be contiguous (:batch) or shuffled (:scatter). If `scatter` is chosen, then your reducing operator `op` **must** be [commutative](https://en.wikipedia.org/wiki/Commutative_property) in addition to being associative, or you could get incorrect results!
- `schedule::Symbol` either `:dynamic` or `:static` (default `:dynamic`), determines how the parallel portions of the calculation are scheduled. `:dynamic` scheduling is generally preferred since it is more flexible and better at load balancing, but `:static` scheduling can sometimes be more performant when the time it takes to complete a step of the calculation is highly uniform, and no other parallel functions are running at the same time.
"""
function tmap end

"""
    tmap!(f, out, A::AbstractArray;
          nchunks::Int = nthreads(),
          split::Symbol = :batch,
          schedule::Symbol =:dynamic)

A multithreaded function like `Base.map!`. In parallel on multiple tasks, this function assigns each element
of `out[i] = f(A[i])` for each index `i` of `A` and `out`.

## Keyword arguments:

- `nchunks::Int` (default `nthreads()`) is passed to `ChunkSplitters.chunks` to inform it how many pieces of data should be worked on in parallel. Greater `nchunks` typically helps with [load balancing](https://en.wikipedia.org/wiki/Load_balancing_(computing)), but at the expense of creating more overhead.
- `split::Symbol` (default `:batch`) is passed to `ChunkSplitters.chunks` to inform it if the data chunks to be worked on should be contiguous (:batch) or shuffled (:scatter). If `scatter` is chosen, then your reducing operator `op` **must** be [commutative](https://en.wikipedia.org/wiki/Commutative_property) in addition to being associative, or you could get incorrect results!
- `schedule::Symbol` either `:dynamic` or `:static` (default `:dynamic`), determines how the parallel portions of the calculation are scheduled. `:dynamic` scheduling is generally preferred since it is more flexible and better at load balancing, but `:static` scheduling can sometimes be more performant when the time it takes to complete a step of the calculation is highly uniform, and no other parallel functions are running at the same time.
"""
function tmap! end

"""
    tcollect([OutputElementType], gen::Union{AbstractArray, Generator{<:AbstractArray}};
             nchunks::Int = nthreads(),
             schedule::Symbol =:dynamic)

A multithreaded function like `Base.collect`. Essentially just calls `tmap` on the generator function and
inputs. The optional argument `OutputElementType` will select a specific element type for the returned container, and will generally incur fewer allocations than the version where `OutputElementType` is not specified.

## Keyword arguments:

- `nchunks::Int` (default `nthreads()`) is passed to `ChunkSplitters.chunks` to inform it how many pieces of data should be worked on in parallel. Greater `nchunks` typically helps with [load balancing](https://en.wikipedia.org/wiki/Load_balancing_(computing)), but at the expense of creating more overhead.
- `schedule::Symbol` either `:dynamic` or `:static` (default `:dynamic`), determines how the parallel portions of the calculation are scheduled. `:dynamic` scheduling is generally preferred since it is more flexible and better at load balancing, but `:static` scheduling can sometimes be more performant when the time it takes to complete a step of the calculation is highly uniform, and no other parallel functions are running at the same time.
"""
function tcollect end

include("tools.jl")
include("implementation.jl")


end # module OhMyThreads
