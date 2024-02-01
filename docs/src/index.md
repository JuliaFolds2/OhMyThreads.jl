# OhMyThreads.jl

[OhMyThreads.jl](https://github.com/JuliaFolds2/OhMyThreads.jl/) is meant to be a simple, unambitious package that provides user-friendly ways of doing task-parallel multithreaded calculations via higher-order functions, with a
focus on [data parallelism](https://en.wikipedia.org/wiki/Data_parallelism) without needing to expose julia's
[Task](https://docs.julialang.org/en/v1/base/parallel/) model to users.

## Installation

The package is registered. Hence, you can simply use
```
] add OhMyThreads
```
to add the package to your Julia environment.

## Noteworthy Alternatives

* [ThreadsX.jl](https://github.com/tkf/ThreadsX.jl)
* [Folds.jl](https://github.com/JuliaFolds/Folds.jl)

## Acknowledgements

The idea for this package came from [Carsten Bauer](https://github.com/carstenbauer) and [Mason Protter](https://github.com/MasonProtter). Check out the [list of contributors](https://github.com/JuliaFolds2/OhMyThreads.jl/graphs/contributors) for more information.