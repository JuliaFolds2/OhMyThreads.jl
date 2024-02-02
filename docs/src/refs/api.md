# [Public API](@id API)

## Index

```@index
Pages   = ["api.md"]
Order   = [:function, :macro]
```

## Exported

```@docs
tmapreduce
treduce
tmap
tmap!
tforeach
tcollect
treducemap
```

as well as the following re-exported functions:

|                        |                                                                     |
|------------------------|---------------------------------------------------------------------|
| `chunks`   | see [ChunkSplitters.jl](https://juliafolds2.github.io/ChunkSplitters.jl/dev/references/#ChunkSplitters.chunks) |

## Non-Exported

|                        |                                                                     |
|------------------------|---------------------------------------------------------------------|
| `OhMyThreads.@spawn`   | see [StableTasks.jl](https://github.com/JuliaFolds2/StableTasks.jl) |
| `OhMyThreads.@spawnat` | see [StableTasks.jl](https://github.com/JuliaFolds2/StableTasks.jl) |
