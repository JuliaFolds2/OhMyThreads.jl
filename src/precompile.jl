# Precompiles the entry points of the team schedulers, the `boxed_captures` generator and
# the region functions of ThreadTeams.jl (`run_fold`, `dispatch!`, ...) for sample loop
# bodies; inferring them also compiles the compiler specializations they need (about 0.3 s
# per session otherwise). Parallel operations on the team run serially during
# precompilation, so the workload starts no tasks.
if ccall(:jl_generating_output, Cint, ()) == 1
    let x = zeros(2), team = TeamScheduler(), greedy = GreedyTeamScheduler()
        tforeach(i -> (x[i] = 1.0), eachindex(x); scheduler = team)
        tmapreduce(abs2, +, x; scheduler = team)
        tmap(sqrt, x; scheduler = team)
        tforeach(i -> (x[i] = 1.0), eachindex(x); scheduler = greedy)
        tmapreduce(abs2, +, x; scheduler = greedy)
        @tasks for i in eachindex(x)
            @set scheduler = team
            x[i] = 2.0
        end
    end
end
