# ThreadsBasics

#### This package is in very early development and is not yet registered

This is meant to be a simple, unambitious package that provides basic, user-friendly ways of doing 
multithreaded calculations via higher-order functions, with a focus on [data parallelism](https://en.wikipedia.org/wiki/Data_parallelism).

It provides

- `tmap(f, ::Type{OutputType}, A::AbstractArray)` which `map`s
the function `f` over the array `A` assuming that the output type of `f` is `OutputType`.
- `tmap!(f, out, A::AbstractArray)` which is like `tmap` except instead of creating an output container of a certain element type, it mutates a provided container `out` such that `out[i] = f(A[i])`, (i.e. a parallelized version of `Base.map!`).
- `tforeach(f, itr)` which is like `Base.foreach` except parallelized over multiple tasks, simply calling the function `f` on each element of `itr`.
    - The iterable `itr` can be any type which supports `halve` and `amount` from [SplittablesBase.jl](https://github.com/JuliaFolds2/SplittablesBase.jl).
- `treduce(op, itr; [init])` which is a parallelized version of `Base.reduce`, combining each element of `itr` with a two-argument function `op`. Reduce may seem unfamiliar to some, but the function `sum(A)` is simply `reduce(+, A)`, for example.
    - `op` must be [associative](https://en.wikipedia.org/wiki/Associative_property) in the sense that `op(a, op(b, c)) ≈ op(op(a, b), c)`.
	- The reduction is performed in a tree-like manner.
    - The iterable `itr` can be any type which supports `halve` and `amount` from [SplittablesBase.jl](https://github.com/JuliaFolds2/SplittablesBase.jl).
- `tmapreduce(f, op, itr)` which is a parallelized version of `Base.mapreduce`, applying a one-argument function `f` to each element of `itr` and combining them with a two-argument function `op`. Mapreduce may seem unfamiliar to some, but the function `sum(f, A)` is simply `mapreduce(f, +, A)`, for example.
    - `op` must be [associative](https://en.wikipedia.org/wiki/Associative_property) in the sense that `op(a, op(b, c)) ≈ op(op(a, b), c)`.
	- The reduction is performed in a tree-like manner.
	- The iterable `itr` can be any type which supports `halve` and `amount` from [SplittablesBase.jl](https://github.com/JuliaFolds2/SplittablesBase.jl).
- `treducemap(op, f, itr; [init]) = tmapreduce(f, op, itr; [init])` because sometimes this is more convenient for `do`-block notation, depending on the calculation. 


Users can provide *either* `chunk_size`, or `chunks_per_thread` (and if both are provided, `chunk_size` is used) to all of these functions 
- `chunks_per_thread` (defaults `2`), will try to split up `itr` so that each thread will recieve *approximately* `chunks_per_thread` pieces of data to work on. More `chunks_per_thread`, typically means better [load balancing](https://en.wikipedia.org/wiki/Load_balancing_(computing)).
- `chunk_size` (computed based on `chunks_per_thread` by deault). Data from `itr` will be divided in half using `halve` from [SplittablesBase.jl](https://github.com/JuliaFolds2/SplittablesBase.jl) until those chunks have an `SplittablesBase.amount` less than or equal to `chunk_size`.
