```@meta
EditURL = "boxing.jl"
```

# Boxed Variables

All multithreading in julia is built around the idea of passing around
and executing functions, but often these functions "enclose" data from
an outer local scope, making them what's called a "closure".

Julia allows functions which capture variables to re-bind those variables
to different values, but doing so can cause subtle race conditions in
multithreaded code.

Consider the following example:

````julia
let out = zeros(Int, 10)
    Threads.@threads for i in 1:10
        A = i
        sleep(1/100)
        out[i] = A
    end
    A = 1
    out
end
````

````
10-element Vector{Int64}:
 6
 2
 3
 2
 3
 2
 3
 2
 3
 4
````

You may have expected that to return `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]`,
but the nonsense result is caused by `A` actually being a shared mutable
container here which all the parallel tasks are accessing and mutating
in parallel, giving unpredictable results.

OhMyThreads.jl tries to protect users from this surprising behaviour:

````julia
using OhMyThreads

try
    let
        # this throws an error!
        out = tmap(1:10) do i
            A = i
            sleep(1/100)
            A
        end
        A = 1
        out
    end
catch e;
    println(e.msg) # show that error
end
````

````
Attempted to capture and modify outer local variable(s) A, which would be not only slow, but could also cause a race condition. Consider marking these variables as local inside their respective closure, or redesigning your code to avoid the race condition.

If these variables are inside a @one_by_one or @only_one block, consider using a mutable Ref instead of re-binding the variable.

This error can be bypassed with the @allow_boxed_captures macro.

````

If you really desire to bypass this behaviour, you can use the
`@allow_boxed_captures` macro

````julia
@allow_boxed_captures let
    out = tmap(1:10) do i
        A = i
        sleep(1/100)
        A
    end
    A = 1
    out
end
````

````
10-element Vector{Int64}:
 7
 6
 7
 6
 7
 6
 7
 6
 7
 7
````

---

*This page was generated using [Literate.jl](https://github.com/fredrikekre/Literate.jl).*

