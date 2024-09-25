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
@only_one
@one_by_one
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

## Re-exported

|                        |                                                                     |
|------------------------|---------------------------------------------------------------------|
| `OhMyThreads.chunks`   | see [ChunkSplitters.jl](https://juliafolds2.github.io/ChunkSplitters.jl/stable/references/#ChunkSplitters.chunks) |
| `OhMyThreads.index_chunks`   | see [ChunkSplitters.jl](https://juliafolds2.github.io/ChunkSplitters.jl/stable/references/#ChunkSplitters.index_chunks) |

## Public but not exported

|                        |                                                                     |
|------------------------|---------------------------------------------------------------------|
| `OhMyThreads.@spawn`   | see [StableTasks.jl](https://github.com/JuliaFolds2/StableTasks.jl) |
| `OhMyThreads.@spawnat` | see [StableTasks.jl](https://github.com/JuliaFolds2/StableTasks.jl) |
| `OhMyThreads.@fetch`   | see [StableTasks.jl](https://github.com/JuliaFolds2/StableTasks.jl) |
| `OhMyThreads.@fetchfrom` | see [StableTasks.jl](https://github.com/JuliaFolds2/StableTasks.jl) |
| `OhMyThreads.TaskLocalValue`   | see [TaskLocalValues.jl](https://github.com/vchuravy/TaskLocalValues.jl) |
| `OhMyThreads.Split`   | see [ChunkSplitters.jl](https://juliafolds2.github.io/ChunkSplitters.jl/stable/references/#ChunkSplitters.Split) |
| `OhMyThreads.Consecutive`   | see [ChunkSplitters.jl](https://juliafolds2.github.io/ChunkSplitters.jl/stable/references/#ChunkSplitters.Consecutive) |
| `OhMyThreads.RoundRobin`   | see [ChunkSplitters.jl](https://juliafolds2.github.io/ChunkSplitters.jl/stable/references/#ChunkSplitters.RoundRobin) |


```@docs
OhMyThreads.WithTaskLocals
OhMyThreads.promise_task_local
```
