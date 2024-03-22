module Experimental

"""
    @barrier

This can be used inside a `@tasks for ... end` to synchronize `n` parallel tasks.
Specifically, a task can only pass the `@barrier` if `n-1` other tasks have reached it
as well. The value of `n` is determined from `@set ntasks=...`, which
is required if one wants to use `@barrier`.

Because this feature is experimental, it is required to load `@barrier` explicitly, e.g. via
`using OhMyThreads.Experimental: @barrier`.

**WARNING:** It is the responsibility of the user to ensure that the right number of tasks
actually reach the barrier. Otherwise, a **deadlock** can occur. In partictular, if the
number of iterations is not a multiple of `n`, the last few iterations (remainder) will be
run by less than `n` tasks which will never be able to pass a `@barrier`.

## Example

```julia
using OhMyThreads: @tasks

# works
@tasks for i in 1:20
    @set ntasks = 20

    sleep(i * 0.2)
    println(i, ": before")
    @barrier
    println(i, ": after")
end

# wrong - deadlock!
@tasks for i in 1:22 # ntasks % niterations != 0
    @set ntasks = 20

    println(i, ": before")
    @barrier
    println(i, ": after")
end
```
"""
macro barrier(args...)
    error("The @barrier macro may only be used inside of a @tasks block.")
end

end # Experimental
