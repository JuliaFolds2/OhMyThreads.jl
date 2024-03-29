# OhMyThreads.jl

[OhMyThreads.jl](https://github.com/JuliaFolds2/OhMyThreads.jl/) is meant to be a simple, unambitious package that provides user-friendly ways of doing [task-based](https://docs.julialang.org/en/v1/base/parallel/) multithreaded calculations in Julia. Most importantly, with a
focus on [data parallelism](https://en.wikipedia.org/wiki/Data_parallelism), it provides an [API of higher-order functions](https://juliafolds2.github.io/OhMyThreads.jl/stable/refs/api/#Functions) (e.g. `tmapreduce`) as well as a [macro API](https://juliafolds2.github.io/OhMyThreads.jl/stable/refs/api/#Macros) `@tasks for ... end` (conceptually similar to `@threads`).

## Quick Start

The package is registered. Hence, you can simply use
```
] add OhMyThreads
```
to add the package to your Julia environment.

### Basic example

```julia
using OhMyThreads: tmapreduce, @tasks
using BenchmarkTools: @btime
using Base.Threads: nthreads

# Variant 1: function API
function mc_parallel(N; ntasks=nthreads())
    M = tmapreduce(+, 1:N; ntasks) do i
        rand()^2 + rand()^2 < 1.0
    end
    pi = 4 * M / N
    return pi
end

# Variant 2: macro API
function mc_parallel_macro(N; ntasks=nthreads())
    M = @tasks for i in 1:N
        @set begin
            reducer=+
            ntasks=ntasks
        end
        rand()^2 + rand()^2 < 1.0
    end
    pi = 4 * M / N
    return pi
end

N = 100_000_000
mc_parallel(N) # gives, e.g., 3.14159924

@btime mc_parallel($N; ntasks=1) # use a single task (and hence a single thread)
@btime mc_parallel($N)           # using all threads
@btime mc_parallel_macro($N)     # using all threads
```

With 5 threads, timings might be something like this:

```
417.282 ms (14 allocations: 912 bytes)
83.578 ms (38 allocations: 3.08 KiB)
83.573 ms (38 allocations: 3.08 KiB)
```

(Check out the full [Parallel Monte Carlo](@ref) example if you like.)

## No Transducers

Unlike most [JuliaFolds2](https://github.com/JuliaFolds2) packages, OhMyThreads.jl is not built off of [Transducers.jl](https://github.com/JuliaFolds2/Transducers.jl), nor is it a building block for Transducers.jl. Rather, it is meant to be a simpler, more maintainable, and more accessible alternative to high-level packages like, e.g., [ThreadsX.jl](https://github.com/tkf/ThreadsX.jl) or [Folds.jl](https://github.com/JuliaFolds2/Folds.jl).

## Acknowledgements

The idea for this package came from [Carsten Bauer](https://github.com/carstenbauer) and [Mason Protter](https://github.com/MasonProtter). Check out the [list of contributors](https://github.com/JuliaFolds2/OhMyThreads.jl/graphs/contributors) for more information.
