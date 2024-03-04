module OhMyThreads

using StableTasks: StableTasks
for mac in Symbol.(["@spawn", "@spawnat", "@fetch", "@fetchfrom"])
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
using .Schedulers: Scheduler, DynamicScheduler, StaticScheduler, GreedyScheduler
include("implementation.jl")

export @tasks, @set, @local
export treduce, tmapreduce, treducemap, tmap, tmap!, tforeach, tcollect
export Scheduler, DynamicScheduler, StaticScheduler, GreedyScheduler

end # module OhMyThreads
