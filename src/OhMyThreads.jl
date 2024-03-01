module OhMyThreads

using StableTasks: StableTasks
for mac ∈ Symbol.(["@spawn", "@spawnat", "@fetch", "@fetchfrom"])
    @eval const $mac = getproperty(StableTasks, $(QuoteNode(mac)))
end

using ChunkSplitters: ChunkSplitters
const chunks = ChunkSplitters.chunks

using TaskLocalValues: TaskLocalValues
const TaskLocalValue = TaskLocalValues.TaskLocalValue

include("functions.jl")
include("macros.jl")

include("tools.jl")
include("schedulers.jl")
using .Schedulers: Scheduler,
    DynamicScheduler, StaticScheduler, GreedyScheduler, SpawnAllScheduler
include("implementation.jl")

export @tasks, @set, @init
export treduce, tmapreduce, treducemap, tmap, tmap!, tforeach, tcollect
export Scheduler, DynamicScheduler, StaticScheduler, GreedyScheduler, SpawnAllScheduler

end # module OhMyThreads
