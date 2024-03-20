module OhMyThreads

using StableTasks: StableTasks
for mac in Symbol.(["@spawn", "@spawnat", "@fetch", "@fetchfrom"])
    @eval const $mac = getproperty(StableTasks, $(QuoteNode(mac)))
end

using ChunkSplitters: ChunkSplitters
const chunks = ChunkSplitters.chunks

using TaskLocalValues: TaskLocalValues
const TaskLocalValue = TaskLocalValues.TaskLocalValue
include("types.jl")
include("functions.jl")
include("macros.jl")

include("tools.jl")
include("schedulers.jl")
using .Schedulers: Scheduler, DynamicScheduler, StaticScheduler, GreedyScheduler,
                   SerialScheduler
include("implementation.jl")

export @tasks, @set, @local, @one_by_one, @only_one
export treduce, tmapreduce, treducemap, tmap, tmap!, tforeach, tcollect
export Scheduler, DynamicScheduler, StaticScheduler, GreedyScheduler, SerialScheduler

end # module OhMyThreads
