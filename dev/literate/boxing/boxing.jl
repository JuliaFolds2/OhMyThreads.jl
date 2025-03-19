#====================================
# Boxed Variables

All multithreading in julia is built around the idea of passing around
and executing functions, but often these functions "enclose" data from
an outer local scope, making them what's called a "closure".

## Boxed variables causing race conditions

Julia allows functions which capture variables to re-bind those variables
to different values, but doing so can cause subtle race conditions in
multithreaded code.

Consider the following example:
====================================#

let out = zeros(Int, 10)
    Threads.@threads for i in 1:10
        A = i
        sleep(1/100)
        out[i] = A
    end
    A = 1
    out
end

#====================================
You may have expected that to return `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]`,
but the nonsense result is caused by `A` actually being a shared mutable
container here which all the parallel tasks are accessing and mutating
in parallel, giving unpredictable results.

OhMyThreads.jl tries to protect users from this surprising behaviour:
====================================#
using OhMyThreads

try
    let
        ## this throws an error!
        out = tmap(1:10) do i
            A = i
            sleep(1/100)
            A
        end
        A = 1
        out
    end
catch e;
    ## Show the error
    Base.showerror(stdout, e)
end

#====================================
In this case, we could fix the race conditon by marking `A` as local:
====================================#

let
    out = tmap(1:10) do i
        local A = i # Note the use of `local`
        sleep(1/100)
        A
    end
    A = 1
    out
end

#====================================
If you really desire to bypass this error, you can use the
`@allow_boxed_captures` macro
====================================#

@allow_boxed_captures let
    out = tmap(1:10) do i
        A = i
        sleep(1/100)
        A
    end
    A = 1
    out
end

#====================================
## Non-race conditon boxed variables

Any re-binding of captured variables can cause boxing, even when that boxing isn't strictly necessary, like the following example where we do not rebind `A` in the loop:
====================================#
try
    let A = 1
        if rand(Bool)
            ## Rebind A, it's now boxed!
            A = 2
        end
        @tasks for i in 1:2
            @show A
        end
    end
catch e;
    println("Yup, that errored!")
end
#====================================
This comes down to how julia parses and lowers code. To avoid this, you can use an inner `let` block to localize `A` to the loop:
====================================#

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

#====================================
OhMyThreads provides a macro `@localize` to automate this process:
====================================#

let A = 1
    if rand(Bool)
        A = 2
    end
    ## This stops A from being boxed!
    @localize A @tasks for i in 1:2
        @show A
    end
end

