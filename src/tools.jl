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
    @atomic latch::Bool
    OnlyOneRegion() = new(false)
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
    latch = @atomic :monotonic s.latch
    if latch
        return
    end
    (_, success) = @atomicreplace s.latch false=>true
    if !success
        return
    end
    f()
    return
end

"""
Reset the `OnlyOneRegion` (so that it can be used again).
"""
function reset!(s::OnlyOneRegion)
    @atomicreplace s.latch true=>false
    nothing
end

end # Tools
