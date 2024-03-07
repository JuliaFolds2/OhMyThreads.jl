```@meta
CollapsedDocStrings = true
```

# [Public API](@id API)

## Exported

### Macros
```@docs
@tasks
@set
@local
```

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
SerialScheduler
```

## Non-Exported

|                        |                                                                     |
|------------------------|---------------------------------------------------------------------|
| `OhMyThreads.@spawn`   | see [StableTasks.jl](https://github.com/JuliaFolds2/StableTasks.jl) |
| `OhMyThreads.@spawnat` | see [StableTasks.jl](https://github.com/JuliaFolds2/StableTasks.jl) |
| `OhMyThreads.@fetch`   | see [StableTasks.jl](https://github.com/JuliaFolds2/StableTasks.jl) |
| `OhMyThreads.@fetchfrom` | see [StableTasks.jl](https://github.com/JuliaFolds2/StableTasks.jl) |
| `OhMyThreads.chunks`   | see [ChunkSplitters.jl](https://juliafolds2.github.io/ChunkSplitters.jl/dev/references/#ChunkSplitters.chunks) |
| `OhMyThreads.TaskLocalValue`   | see [TaskLocalValues.jl](https://github.com/vchuravy/TaskLocalValues.jl) |


```@docs
OhMyThreads.WithTaskLocals
OhMyThreads.promise_task_local
```
