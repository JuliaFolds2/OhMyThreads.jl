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
mutable struct OneOnlyRegion
    @atomic latch::Bool
    OneOnlyRegion() = new(false)
end

"""
    try_enter!(f, s::OneOnlyRegion)

When called from multiple parallel tasks (on a shared `s::OneOnlyRegion`) only a single
task will execute `f`.

## Example

```julia
using OhMyThreads: @tasks
using OhMyThreads.Tools: OneOnlyRegion, try_enter!

one_only = OneOnlyRegion()

@tasks for i in 1:10
    @set ntasks = 10

    println(i, ": before")
    try_enter!(one_only) do
        println(i, ": only printed by a single task")
        sleep(1)
    end
    println(i, ": after")
end
```
"""
function try_enter!(f, s::OneOnlyRegion)
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
Reset the `OneOnlyRegion` (so that it can be used again).
"""
function reset!(s::OneOnlyRegion)
    @atomicreplace s.latch true=>false
    nothing
end

end # Tools
