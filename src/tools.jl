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
May be used to mark a region in parallel code to be executed by a single task only
(all other tasks shall skip over it).

See [`try_enter!`](@ref) and [`reset!`](@ref).
"""
mutable struct OnlyOneRegion
    @atomic task::Union{Task, Nothing}
    OnlyOneRegion() = new(nothing)
end

"""
    try_enter!(f, s::OnlyOneRegion)

When called from multiple parallel tasks (on a shared `s::OnlyOneRegion`) only a single
task will execute `f`.

## Example

```julia
using OhMyThreads: @tasks
using OhMyThreads.Tools: OnlyOneRegion, try_enter!

only_one = OnlyOneRegion()

@tasks for i in 1:10
    @set ntasks = 10

    println(i, ": before")
    try_enter!(only_one) do
        println(i, ": only printed by a single task")
        sleep(1)
    end
    println(i, ": after")
end
```
"""
function try_enter!(f, s::OnlyOneRegion)
    ct = current_task()
    t = @atomic :monotonic s.task
    if !isnothing(t) && ct != t
        return
    end
    if ct == t || (@atomicreplace s.task nothing=>ct).success
        f()
    end
    return
end

"""
Reset the `OnlyOneRegion` (so that it can be used again).
"""
function reset!(s::OnlyOneRegion)
    @atomic s.task = nothing
    return
end

"""
SimpleBarrier(n::Integer)

Simple reusable barrier for `n` parallel tasks.

Given `b = SimpleBarrier(n)` and `n` parallel tasks, each task that calls
`wait(b)` will block until the other `n-1` tasks have called `wait(b)` as well.

## Example
```
n = nthreads()
barrier = SimpleBarrier(n)
@sync for i in 1:n
    @spawn begin
        println("A")
        wait(barrier) # synchronize all tasks
        println("B")
        wait(barrier) # synchronize all tasks (reusable)
        println("C")
    end
end
```
"""
mutable struct SimpleBarrier
    const n::Int64
    const c::Threads.Condition
    cnt::Int64

    function SimpleBarrier(n::Integer)
        new(n, Threads.Condition(), 0)
    end
end

function Base.wait(b::SimpleBarrier)
    lock(b.c)
    try
        b.cnt += 1
        if b.cnt == b.n
            b.cnt = 0
            notify(b.c)
        else
            wait(b.c)
        end
    finally
        unlock(b.c)
    end
end

end # Tools
