# [Public API](@id API)

## Index

```@index
Pages   = ["api.md"]
Order   = [:function, :macro, :type]
```

## Exported

### Functions

```@docs
tmapreduce
treduce
tmap
tmap!
tforeach
tcollect
treducemap
```

### Schedulers

```@docs
Scheduler
DynamicScheduler
StaticScheduler
GreedyScheduler
SpawnAllScheduler
```

## Non-Exported

|                        |                                                                     |
|------------------------|---------------------------------------------------------------------|
| `OhMyThreads.@spawn`   | see [StableTasks.jl](https://github.com/JuliaFolds2/StableTasks.jl) |
| `OhMyThreads.@spawnat` | see [StableTasks.jl](https://github.com/JuliaFolds2/StableTasks.jl) |
| `OhMyThreads.chunks`   | see [ChunkSplitters.jl](https://juliafolds2.github.io/ChunkSplitters.jl/dev/references/#ChunkSplitters.chunks) |
| `OhMyThreads.TaskLocalValue`   | see [TaskLocalValues.jl](https://github.com/vchuravy/TaskLocalValues.jl) |
