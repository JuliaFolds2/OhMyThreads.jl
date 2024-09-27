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
| `OhMyThreads.chunks`   | see [`ChunkSplitters.chunks`](@extref) |
| `OhMyThreads.index_chunks`   | see [`ChunkSplitters.index_chunks`](@extref) |

## Public but not exported

|                        |                                                                     |
|------------------------|---------------------------------------------------------------------|
| `OhMyThreads.@spawn`   | see [`StableTasks.@spawn`](https://github.com/JuliaFolds2/StableTasks.jl) |
| `OhMyThreads.@spawnat` | see [`StableTasks.@spawnat`](https://github.com/JuliaFolds2/StableTasks.jl) |
| `OhMyThreads.@fetch`   | see [`StableTasks.@fetch`](https://github.com/JuliaFolds2/StableTasks.jl) |
| `OhMyThreads.@fetchfrom` | see [`StableTasks.@fetchfrom`](https://github.com/JuliaFolds2/StableTasks.jl) |
| `OhMyThreads.TaskLocalValue`   | see [TaskLocalValues.TaskLocalValue](https://github.com/vchuravy/TaskLocalValues.jl) |
| `OhMyThreads.Split`   | see [`ChunkSplitters.Split`](@extref) |
| `OhMyThreads.Consecutive`   | see [`ChunkSplitters.Consecutive`](@extref) |
| `OhMyThreads.RoundRobin`   | see [`ChunkSplitters.RoundRobin`](@extref) |


```@docs
OhMyThreads.WithTaskLocals
OhMyThreads.promise_task_local
OhMyThreads.ChannelLike
```
