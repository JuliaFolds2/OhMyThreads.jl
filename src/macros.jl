"""
    @tasks for ... end

A macro to parallelize a `for` loop by spawning a set of tasks that can be run in parallel.
The policy of how many tasks to spawn and how to distribute the iteration space among the
tasks (and more) can be configured via `@set` statements in the loop body.

Supports reductions (`@set reducer=<reducer function>`) and collecting the results
(`@set collect=true`).

Under the hood, the `for` loop is translated into corresponding parallel
[`tforeach`](@ref), [`tmapreduce`](@ref), or [`tmap`](@ref) calls.

See also: [`@set`](@ref), [`@local`](@ref)

## Examples

```julia
@tasks for i in 1:3
    println(i)
end
```

```julia
@tasks for x in rand(10)
    @set reducer=+
    sin(x)
end
```

```julia
@tasks for i in 1:5
    @set collect=true
    i^2
end
```

```julia
@tasks for i in 1:5
    @set scheduler=:static
    println("i=", i, " → ", threadid())
end

```
```julia
@tasks for i in 1:100
    @set scheduler=DynamicScheduler(; nchunks=4*nthreads())
    # non-uniform work...
end
```
"""
macro tasks(args...)
    Implementation.tasks_macro(args...)
end

"""
    @set name = value

This can be used inside a `@tasks for ... end` block to specify settings for the parallel
execution of the loop.

Multiple settings are supported, either as separate `@set` statements or via
`@set begin ... end`.

## Settings

* `scheduler` (e.g. `scheduler=:static`): Can be either a [`Scheduler`](@ref) or a `Symbol` (e.g. `:dynamic` or `:static`)
* `reducer` (e.g. `reducer=+`): Indicates that a reduction should be performed with the provided binary function. See [`tmapreduce`](@ref) for more information.
* `collect` (e.g. `collect=true`): Indicates that results should be collected (similar to `map`).
"""
macro set(args...)
    error("The @set macro may only be used inside of a @tasks block.")
end

"""
    @local name::T = value

Can be used inside a `@tasks for ... end` block to specify
[task-local values](@ref TLS) (TLV) via explicitly typed assignments.
These values will be allocated once per task
(rather than once per iteration) and can be re-used between different task-local iterations.

There can only be a single `@local` block in a `@tasks for ... end` block. To specify
multiple TLVs, use `@local begin ... end`. Compared to regular assignments, there are some
limitations though, e.g. TLVs can't reference each other.

## Examples

```julia
using OhMyThreads.Tools: taskid
@tasks for i in 1:10
    @set scheduler=DynamicScheduler(; nchunks=2)
    @local x::Vector{Float64} = zeros(3) # TLV

    x .+= 1
    println(taskid(), " -> ", x)
end
```

```julia
@tasks for i in 1:10
    @local begin
        x::Vector{Int64} = rand(Int, 3)
        M::Matrix{Float64} = rand(3, 3)
    end
    # ...
end
```
"""
macro init(args...)
    error("The @local macro may only be used inside of a @tasks block.")
end
