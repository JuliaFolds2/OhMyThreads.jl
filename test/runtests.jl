using ParallelTestRunner
using OhMyThreads

@info "Testing with $(Threads.nthreads(:default)),$(Threads.nthreads(:interactive)) threads."

const init_code = quote
    using Test, OhMyThreads
    using OhMyThreads: TaskLocalValue, WithTaskLocals, @fetch, promise_task_local
    using OhMyThreads: Consecutive, RoundRobin
    using OhMyThreads.Experimental: @barrier
    using OhMyThreads.Implementation: BoxedVariableError

    ChunkedGreedy(; kwargs...) = GreedyScheduler(; kwargs...)
end

# Worker processes don't inherit the thread configuration of this process.
const exeflags = ["--threads=$(Threads.nthreads(:default)),$(Threads.nthreads(:interactive))"]

runtests(OhMyThreads, ARGS; init_code, exeflags)
