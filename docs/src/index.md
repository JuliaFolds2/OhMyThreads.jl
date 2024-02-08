# OhMyThreads.jl

[OhMyThreads.jl](https://github.com/JuliaFolds2/OhMyThreads.jl/) is meant to be a simple, unambitious package that provides user-friendly ways of doing task-parallel multithreaded calculations in Julia. Most importantly, it provides an API of higher-order functions, with a
focus on [data parallelism](https://en.wikipedia.org/wiki/Data_parallelism), that can be used without having to worry much about manual [Task](https://docs.julialang.org/en/v1/base/parallel/) creation.

## Quick Start

The package is registered. Hence, you can simply use
```
] add OhMyThreads
```
to add the package to your Julia environment.

### Basic example

```julia
using OhMyThreads

function mc_parallel(N; kw...)
    M = tmapreduce(+, 1:N; kw...) do i
        rand()^2 + rand()^2 < 1.0
    end
    pi = 4 * M / N
    return pi
end

N = 100_000_000
mc_parallel(N) # gives, e.g., 3.14159924

using BenchmarkTools

@show Threads.nthreads()                                        # 5 in this example

@btime mc_parallel($N; scheduler=DynamicScheduler(; nchunks=1))   # effectively using 1 thread
@btime mc_parallel($N)                                          # using all 5 threads
```

Timings might be something like this:

```
447.093 ms (7 allocations: 624 bytes)
89.401 ms (66 allocations: 5.72 KiB)
```

(Check out the full [Parallel Monte Carlo](@ref) example if you like.)

## No Transducers

Unlike most [JuliaFolds2](https://github.com/JuliaFolds2) packages, OhMyThreads.jl is not built off of [Transducers.jl](https://github.com/JuliaFolds2/Transducers.jl), nor is it a building block for Transducers.jl. Rather, it is meant to be a simpler, more maintainable, and more accessible alternative to high-level packages like, e.g., [ThreadsX.jl](https://github.com/tkf/ThreadsX.jl) or [Folds.jl](https://github.com/JuliaFolds2/Folds.jl).

## Acknowledgements

The idea for this package came from [Carsten Bauer](https://github.com/carstenbauer) and [Mason Protter](https://github.com/MasonProtter). Check out the [list of contributors](https://github.com/JuliaFolds2/OhMyThreads.jl/graphs/contributors) for more information.