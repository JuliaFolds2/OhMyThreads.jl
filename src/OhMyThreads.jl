module OhMyThreads

using StableTasks: StableTasks
for mac in Symbol.(["@spawn", "@spawnat", "@fetch", "@fetchfrom"])
    @eval const $mac = getproperty(StableTasks, $(QuoteNode(mac)))
end

using ChunkSplitters: ChunkSplitters
const index_chunks = ChunkSplitters.index_chunks
const chunks = ChunkSplitters.chunks
const Split = ChunkSplitters.Split
const Consecutive = ChunkSplitters.Consecutive
const RoundRobin = ChunkSplitters.RoundRobin
export chunks, index_chunks

using TaskLocalValues: TaskLocalValues
const TaskLocalValue = TaskLocalValues.TaskLocalValue

using ScopedValues: ScopedValues, ScopedValue, @with

include("types.jl")
include("functions.jl")
include("macros.jl")

include("tools.jl")
include("schedulers.jl")
using .Schedulers: Scheduler, DynamicScheduler, StaticScheduler, GreedyScheduler,
                   SerialScheduler
include("implementation.jl")
include("experimental.jl")

export @tasks, @set, @local, @one_by_one, @only_one, @allow_boxed_captures, @disallow_boxed_captures
export treduce, tmapreduce, treducemap, tmap, tmap!, tforeach, tcollect
export Scheduler, DynamicScheduler, StaticScheduler, GreedyScheduler, SerialScheduler

end # module OhMyThreads
