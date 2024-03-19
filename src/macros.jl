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
using OhMyThreads: @tasks
```

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
@tasks for i in 1:100
    @set ntasks=4*nthreads()
    # non-uniform work...
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
    @set begin
        scheduler=:static
        chunksize=10
    end
    println("i=", i, " → ", threadid())
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

* `reducer` (e.g. `reducer=+`): Indicates that a reduction should be performed with the provided binary function. See [`tmapreduce`](@ref) for more information.
* `collect` (e.g. `collect=true`): Indicates that results should be collected (similar to `map`).

All other settings will be passed on to the underlying parallel functions (e.g. [tmapreduce](@ref))
as keyword arguments. Hence, you may provide whatever these functions accept as
keyword arguments. Among others, this includes

* `scheduler` (e.g. `scheduler=:static`): Can be either a [`Scheduler`](@ref) or a `Symbol` (e.g. `:dynamic`, `:static`, `:serial`, or `:greedy`).
* `init` (e.g. `init=0.0`): Initial value to be used in a reduction (requires `reducer=...`).

Settings like `ntasks`, `chunksize`, and `split` etc. can be used to tune the scheduling policy (if the selected scheduler supports it).

"""
macro set(args...)
    error("The @set macro may only be used inside of a @tasks block.")
end

@eval begin
    """
        @local name = value

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
    using OhMyThreads: @tasks
    using OhMyThreads.Tools: taskid

    @tasks for i in 1:10
        @set begin
            scheduler=:dynamic
            ntasks=2
        end
        @local x = zeros(3) # TLV

        x .+= 1
        println(taskid(), " -> ", x)
    end
    ```

    ```julia
    @tasks for i in 1:10
        @local begin
            x = rand(Int, 3)
            M = rand(3, 3)
        end
        # ...
    end
    ```

    Task local variables created by `@local` are by default constrained to their inferred type,
    but if you need to, you can specify a different type during declaration:
    ```julia
    @tasks for i in 1:10
        @local x::Vector{Float64} = some_hard_to_infer_setup_function()
        # ...
    end
    ```
    """
    macro $(Symbol("local"))(args...)
        error("The @local macro may only be used inside of a @tasks block.")
    end
end

"""
    @only_one begin ... end

This can be used inside a `@tasks for ... end` block to mark a region of code to be
executed by only one of the parallel tasks (all other tasks skip over this region).

## Example

```julia
using OhMyThreads: @tasks

@tasks for i in 1:10
    @set ntasks = 10

    println(i, ": before")
    @only_one begin
        println(i, ": only printed by a single task")
        sleep(1)
    end
    println(i, ": after")
end
```
"""
macro only_one(args...)
    error("The @only_one macro may only be used inside of a @tasks block.")
end

"""
    @one_by_one begin ... end

This can be used inside a `@tasks for ... end` block to mark a region of code to be
executed by one parallel task at a time (i.e. exclusive access). The order may be arbitrary
and non-deterministic.

## Example

```julia
using OhMyThreads: @tasks

@tasks for i in 1:10
    @set ntasks = 10

    println(i, ": before")
    @one_by_one begin
        println(i, ": one task at a time")
        sleep(0.5)
    end
    println(i, ": after")
end
```
"""
macro one_by_one(args...)
    error("The @one_by_one macro may only be used inside of a @tasks block.")
end
