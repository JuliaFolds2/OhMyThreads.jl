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
    Implementation.tasks_macro(args...; __module__)
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

Note that the assignment is hoisted above the loop body which means that the scope is *not*
the scope of the loop (even though it looks like it) but rather the scope *surrounding* the
loop body. (`@macroexpand` is a useful tool to inspect the generated code of the `@tasks`
block.)
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

    The right hand side of the assignment is hoisted outside of the loop body and captured
    as a closure used to initialize the task local value. This means that the scope of the
    closure is *not* the scope of the loop (even though it looks like it) but rather the
    scope *surrounding* the loop body. (`@macroexpand` is a useful tool to inspect the
    generated code of the `@tasks` block.)
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


const allowing_boxed_captures = ScopedValue(false)

"""
    @allow_boxed_captures expr

By default, OhMyThreads.jl will detect and error on multithreaded code which references local variables
which are 'boxed' -- something that happens if the variable could be re-bound in multiple scopes. This
process can cause very sublte bugs in multithreaded code by creating silent race conditions, e.g.

```julia
let
    function wrong()
        tmap(1:10) do i
            A = i # define A for the first time (lexically)
            sleep(rand()/10)
            A # user is trying to reference local A only
        end
    end
    @show wrong()
    A = 1 # boxed! this hoists "A" to the same variable as in `wrong` but presumably the user wanted a new one
end
```
In this example, you might expect to get `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]`, but you would actually observe
incorrect results because `A` is 'boxed'. The fix for this would be to write something like
```julia
let
    function right()
        tmap(1:10) do i
            local A = i
            sleep(rand()/10)
            A 
        end
    end
    @show right()
    A = 1
end
```

However, if you are really sure you want to bypass OhMyThreads's error mechanism, you can use
`@allow_boxed_captures` to wrap code you believe is okay, e.g.

```julia-repl
julia> let A = 1 
           @allow_boxed_captures tmap(1:10) do i
               A = i
               sleep(rand()/10)
               A # race condition!
           end
       end
10-element Vector{Int64}:
 4
 2
 7
 2
 2
 8
 6
 8
 7
 2
```

This is a dynamically scoped construct, so this effect will apply to *all* nested code inside of `expr`.

See also `@disallow_boxed_captures`
"""
macro allow_boxed_captures(ex)
    quote
        @with allowing_boxed_captures => true $(esc(ex))
    end
end

"""
    @disallow_boxed_captures expr

Disable the effect of `@allow_boxed_captures` for any code in `expr`.

This is a dynamically scoped construct, so this effect will apply to *all* nested code inside of `expr`.

See also `@disallow_boxed_captures`
"""
macro disallow_boxed_captures(ex)
    quote
        @with allowing_boxed_captures => false $(esc(ex))
    end
end

"""
   @localize args... expr

Writing
```
@localize x y z expr
```
is equivalent to writing
```
let x=x, y=y, z=z
    expr
end
```
This is useful for avoiding the boxing of captured variables when working with closures.

See https://juliafolds2.github.io/OhMyThreads.jl/stable/literate/boxing/boxing/ for more information about boxed variables.
"""
macro localize(args...)
    syms = args[1:end-1]
    ex = args[end]
    letargs = map(syms) do sym
        if !(sym isa Symbol)
            throw(ArgumentError("All but the final argument to `@localize` must be symbols! Got $sym"))
        end
        :($sym = $sym)
    end
    esc(:(let $(letargs...)
              $ex
          end))
end
