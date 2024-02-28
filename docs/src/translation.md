# [Translation Guide](@id TG)

This page tries to give a general overview of how to translate patterns written with the built-in tools of [Base.Threads](https://docs.julialang.org/en/v1/base/multi-threading/) using the [OhMyThreads.jl API](@ref API). Note that this should be seen as a rough guide and (intentionally) isn't supposed to replace a systematic introduction into OhMyThreads.jl.

## Basics

### `@threads`

```julia
# Base.Threads
@threads for i in 1:10
    println(i)
end
```

```julia
# OhMyThreads
tforeach(1:10) do i
    println(i)
end
```

#### `:static` scheduling

```julia
# Base.Threads
@threads :static for i in 1:10
    println(i)
end
```

```julia
# OhMyThreads
tforeach(1:10; scheduler=StaticScheduler()) do i
    println(i)
end
```

### `@spawn`

```julia
# Base.Threads
@sync for i in 1:10
    @spawn println(i)
end
```

```julia
# OhMyThreads
tforeach(1:10; scheduler=DynamicScheduler(; nchunks=0)) do i
    println(i)
end
```

## Reduction

No built-in feature in Base.Threads.

```julia
# Base.Threads: basic manual implementation
data = rand(10)
chunks_itr = Iterators.partition(data, length(data) ÷ nthreads())
tasks = map(chunks_itr) do chunk
    @spawn reduce(+, chunk)
end
reduce(+, fetch.(tasks))
```

```julia
# OhMyThreads
data = rand(10)
treduce(+, data)
```

## Mutation

!!! warning
    Parallel mutation of non-local state, like writing to a shared array, can be the source of correctness errors (e.g. race conditions) and big performance issues (e.g. [false sharing](https://en.wikipedia.org/wiki/False_sharing#:~:text=False%20sharing%20is%20an%20inherent,is%20limited%20to%20RAM%20caches.)). You should carefully consider whether this is necessary or whether the use of [thread-safe storage](@ref TSS) is the better option.

```julia
# Base.Threads
data = rand(10)
@threads for i in 1:10
    data[i] = calc(i)
end
```

```julia
# OhMyThreads: Variant 1
data = rand(10)
tforeach(data) do i
    data[i] = calc(i)
end
```

```julia
# OhMyThreads: Variant 2
data = rand(10)
tmap!(data, data) do i # this kind of aliasing is fine
    calc(i)
end
```

## Parallel initialization

```julia
# Base.Threads
data = Vector{Float64}(undef, 10)
@threads for i in 1:10
    data[i] = calc(i)
end
```

```julia
# OhMyThreads: Variant 1
data = tmap(i->calc(i), 1:10)
```

```julia
# OhMyThreads: Variant 2
data = tcollect(calc(i) for i in 1:10)
```
