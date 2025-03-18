```@meta
EditURL = "boxing.jl"
```

# Boxed Variables

All multithreading in julia is built around the idea of passing around
and executing functions, but often these functions "enclose" data from
an outer local scope, making them what's called a "closure".

# ## Boxed variables causing race conditions

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
 10
  4
  8
  4
  2
  4
 10
  4
 10
 10
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
    # Show the error
    Base.showerror(stdout, e)
end
````

````
Attempted to capture and modify outer local variable(s) A.
See https://juliafolds2.github.io/OhMyThreads.jl/stable/literate/boxing/boxing/ for a fuller explanation.

  Capturing boxed variables can be not only slow, but also cause race
  conditions.

    •  If you meant for these variables to be local to each loop
       iteration and not depend on a variable from an outer scope, you
       should mark them as local inside the closure.

    •  If you meant to reference a variable from the outer scope, but do
       not want access to it to be boxed, you can wrap uses of it in a
       let block, like e.g.

  function foo(x, N)
      if rand(Bool)
      x = 1 # This rebinding of x causes it to be boxed ...
      end
      let x = x # ... Unless we localize it here with the let block 
          @tasks for i in 1:N
              f(x)    
          end
      end
  end

    •  OhMyThreads.jl provides a @localize macro that automates the above
       let block, i.e. @localize x f(x) is the same as let x=x; f(x) end

    •  If these variables are being re-bound inside a @one_by_one or
       @only_one block, consider using a mutable Ref instead of
       re-binding the variable.

  This error can be bypassed with the @allow_boxed_captures macro.
````

In this case, we could fix the race conditon by marking `A` as local:

````julia
let
    out = tmap(1:10) do i
        local A = i # Note the use of `local`
        sleep(1/100)
        A
    end
    A = 1
    out
end
````

````
10-element Vector{Int64}:
  1
  2
  3
  4
  5
  6
  7
  8
  9
 10
````

If you really desire to bypass this error, you can use the
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
 2
 7
 2
 7
 2
 7
 2
 7
 7
````

## Non-race conditon boxed variables

Any re-binding of captured variables can cause boxing, even when that boxing isn't strictly necessary, like the following example where we do not rebind `A` in the loop:

````julia
try
    let A = 1
        if rand(Bool)
            # Rebind A, it's now boxed!
            A = 2
        end
        @tasks for i in 1:2
            @show A
        end
    end
catch e;
    println("Yup, that errored!")
end
````

````
Yup, that errored!

````

This comes down to how julia parses and lowers code. To avoid this, you can use an inner `let` block to localize `A` to the loop:

````julia
let A = 1
    if rand(Bool)
        A = 2
    end
    let A = A # This stops A from being boxed!
        @tasks for i in 1:2
            @show A
        end
    end
end
````

````
A = 2
A = 2

````

OhMyThreads provides a macro `@localize` to automate this process:

````julia
let A = 1
    if rand(Bool)
        A = 2
    end
    # This stops A from being boxed!
    @localize A @tasks for i in 1:2
        @show A
    end
end
````

````
A = 2
A = 2

````

---

*This page was generated using [Literate.jl](https://github.com/fredrikekre/Literate.jl).*

