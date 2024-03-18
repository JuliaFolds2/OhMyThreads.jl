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
When `try_enter(s::SectionSingle) do ... end` is called from multiple parallel tasks only
a single task will run the content of the `do ... end` block.
"""
struct SectionSingle
    first::Base.RefValue{Bool}
    lck::ReentrantLock
    SectionSingle() = new(Ref(true), ReentrantLock())
end

"""
    try_enter(f, s::SectionSingle)

When called from multiple parallel tasks (on a shared `s::SectionSingle`) only a single
task will execute `f`. Typical usage:

```julia
using OhMyThreads.Tools: SectionSingle

s = SectionSingle()

@tasks for i in 1:10
    @set ntasks = 10

    println(i, ": before")
    try_enter(s) do
        println(i, ": only printed by a single task")
        sleep(1)
    end
    println(i, ": after")
end
```
"""
function try_enter(f, s::SectionSingle)
    run_f = false
    lock(s.lck) do
        if s.first[]
           run_f = true # The first task to try_enter → run f
           s.first[] = false
        end
    end
    run_f && f()
end

end # Tools
