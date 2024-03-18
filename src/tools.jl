module Tools

using Base.Threads: nthreads

"""
    nthtid(n)

Returns the thread id of the `n`th Julia thread in the `:default` threadpool.
"""
@inline function nthtid(n)
    @static if VERSION < v"1.9"
        @boundscheck 1 <= n <= nthreads()
        return n
    else
        @boundscheck 1 <= n <= nthreads(:default)
        return n + Threads.threadpoolsize(:interactive) # default threads after interactive threads
    end
end

"""
    taskid() :: UInt

Return a `UInt` identifier for the current running [Task](https://docs.julialang.org/en/v1/base/parallel/#Core.Task). This identifier will be unique so long as references to the task it came from still exist.
"""
taskid() = objectid(current_task())

"""
SimpleBarrier(n::Integer)

Simple reusable barrier for `n` parallel tasks.

Given `b = SimpleBarrier(n)` and `n` parallel tasks, each task that calls
`wait(b)` will block until the other `n-1` tasks have called `wait(b)` as well.

## Example
```
using OhMyThreads.Tools: SimpleBarrier, @tasks

n = nthreads()
barrier = SimpleBarrier(n)
@tasks for i in 1:n
    @set ntasks = n

    println("A")
    wait(barrier) # synchronize all tasks
    println("B")
    wait(barrier) # synchronize all tasks (reusable)
    println("C")
end
```
"""
struct SimpleBarrier
    n::Int64
    c::Threads.Condition
    cnt::Base.RefValue{Int64}

    function SimpleBarrier(n::Integer)
        new(n, Threads.Condition(), Base.RefValue{Int64}(0))
    end
end

function Base.wait(b::SimpleBarrier)
    lock(b.c)
    try
        b.cnt[] += 1
        if b.cnt[] == b.n
            b.cnt[] = 0
            notify(b.c)
        else
            wait(b.c)
        end
    finally
        unlock(b.c)
    end
end

end # Tools
