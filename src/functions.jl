"""
    tmapreduce(f, op, A::AbstractArray...;
               [scheduler::Scheduler = DynamicScheduler()],
               [outputtype::Type = Any],
               [init])

A multithreaded function like `Base.mapreduce`. Perform a reduction over `A`, applying a
single-argument function `f` to each element, and then combining them with the two-argument
function `op`.

Note that `op` **must** be an
[associative](https://en.wikipedia.org/wiki/Associative_property) function, in the sense
that `op(a, op(b, c)) ≈ op(op(a, b), c)`. If `op` is not (approximately) associative, you
will get undefined results.

## Example:

```
tmapreduce(√, +, [1, 2, 3, 4, 5])
```

is the parallelized version of `sum(√, [1, 2, 3, 4, 5])` in the form

```
(√1 + √2) + (√3 + √4) + √5
```

## Keyword arguments:

- `scheduler::Scheduler` (default `DynamicScheduler()`): determines how the computation is divided into parallel tasks and how these are scheduled. See [`Scheduler`](@ref) for more information.
- `outputtype::Type` (default `Any`): will work as the asserted output type of parallel calculations. We use [StableTasks.jl](https://github.com/MasonProtter/StableTasks.jl) to make setting this option unnecessary, but if you experience problems with type stability, you may be able to recover it with this keyword argument.
- `init`: forwarded to `mapreduce` for the task-local sequential parts of the calculation.
"""
function tmapreduce end

"""
    treducemap(op, f, A::AbstractArray...;
               [scheduler::Scheduler = DynamicScheduler()],
               [outputtype::Type = Any],
               [init])

Like `tmapreduce` except the order of the `f` and `op` arguments are switched. This is
sometimes convenient with `do`-block notation. Perform a reduction over `A`, applying a
single-argument function `f` to each element, and then combining them with the two-argument
function `op`.

Note that `op` **must** be an
[associative](https://en.wikipedia.org/wiki/Associative_property) function, in the sense
that `op(a, op(b, c)) ≈ op(op(a, b), c)`. If `op` is not (approximately) associative, you
will get undefined results.

## Example:

```
tmapreduce(√, +, [1, 2, 3, 4, 5])
```

is the parallelized version of `sum(√, [1, 2, 3, 4, 5])` in the form

```
(√1 + √2) + (√3 + √4) + √5
```

## Keyword arguments:

- `scheduler::Scheduler` (default `DynamicScheduler()`): determines how the computation is divided into parallel tasks and how these are scheduled. See [`Scheduler`](@ref) for more information.
- `outputtype::Type` (default `Any`): will work as the asserted output type of parallel calculations. We use [StableTasks.jl](https://github.com/MasonProtter/StableTasks.jl) to make setting this option unnecessary, but if you experience problems with type stability, you may be able to recover it with this keyword argument.
- `init`: forwarded to `mapreduce` for the task-local sequential parts of the calculation.
"""
function treducemap end

"""
    treduce(op, A::AbstractArray...;
            [scheduler::Scheduler = DynamicScheduler()],
            [outputtype::Type = Any],
            [init])

A multithreaded function like `Base.reduce`. Perform a reduction over `A` using the
two-argument function `op`.

Note that `op` **must** be an
[associative](https://en.wikipedia.org/wiki/Associative_property) function, in the sense
that `op(a, op(b, c)) ≈ op(op(a, b), c)`. If `op` is not (approximately) associative, you
will get undefined results.

## Example:

```
treduce(+, [1, 2, 3, 4, 5])
```

is the parallelized version of `sum([1, 2, 3, 4, 5])` in the form

```
(1 + 2) + (3 + 4) + 5
```

## Keyword arguments:

- `scheduler::Scheduler` (default `DynamicScheduler()`): determines how the computation is divided into parallel tasks and how these are scheduled. See [`Scheduler`](@ref) for more information.
- `outputtype::Type` (default `Any`): will work as the asserted output type of parallel calculations. We use [StableTasks.jl](https://github.com/MasonProtter/StableTasks.jl) to make setting this option unnecessary, but if you experience problems with type stability, you may be able to recover it with this keyword argument.
- `init`: forwarded to `mapreduce` for the task-local sequential parts of the calculation.
"""
function treduce end

"""
    tforeach(f, A::AbstractArray...;
             [schedule::Scheduler = DynamicScheduler()]) :: Nothing

A multithreaded function like `Base.foreach`. Apply `f` to each element of `A` on
multiple parallel tasks, and return `nothing`. I.e. it is the parallel equivalent of

```
for x in A
    f(x)
end
```

## Example:

```
tforeach(1:10) do i
    println(i^2)
end
```

## Keyword arguments:

- `scheduler::Scheduler` (default `DynamicScheduler()`): determines how the computation is divided into parallel tasks and how these are scheduled. See [`Scheduler`](@ref) for more information.
"""
function tforeach end

"""
    tmap(f, [OutputElementType], A::AbstractArray...;
         [schedule::Scheduler = DynamicScheduler()])

A multithreaded function like `Base.map`. Create a new container `similar` to `A` and fills
it in parallel such that the `i`th element is equal to `f(A[i])`.

The optional argument `OutputElementType` will select a specific element type for the
returned container, and will generally incur fewer allocations than the version where
`OutputElementType` is not specified.

## Example:

```
tmap(sin, 1:10)
```

## Keyword arguments:

- `scheduler::Scheduler` (default `DynamicScheduler()`): determines how the computation is divided into parallel tasks and how these are scheduled. See [`Scheduler`](@ref) for more information.
"""
function tmap end

"""
    tmap!(f, out, A::AbstractArray...;
          [schedule::Scheduler = DynamicScheduler()])

A multithreaded function like `Base.map!`. In parallel on multiple tasks, this function
assigns each element of `out[i] = f(A[i])` for each index `i` of `A` and `out`.

## Keyword arguments:

- `scheduler::Scheduler` (default `DynamicScheduler()`): determines how the computation is divided into parallel tasks and how these are scheduled. See [`Scheduler`](@ref) for more information.
"""
function tmap! end

"""
    tcollect([OutputElementType], gen::Union{AbstractArray, Generator{<:AbstractArray}};
             [schedule::Scheduler = DynamicScheduler()])

A multithreaded function like `Base.collect`. Essentially just calls `tmap` on the
generator function and inputs.

The optional argument `OutputElementType` will select a specific element type for the
returned container, and will generally incur fewer allocations than the version where
`OutputElementType` is not specified.

## Example:

```
tcollect(sin(i) for i in 1:10)
```

## Keyword arguments:

- `scheduler::Scheduler` (default `DynamicScheduler()`): determines how the computation is divided into parallel tasks and how these are scheduled. See [`Scheduler`](@ref) for more information.
"""
function tcollect end
