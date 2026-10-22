# The functions only pass `f` and `op` on, and Julia does not specialize a method on a
# function argument that it only passes on: without type parameters, a call can end up in an
# instance compiled for `::Function`, behind which every call of `f` dispatches dynamically.
# Whether a call site escapes that depends on inlining, so test the shape that did not: a
# closure that captures a run-time value and calls a non-inlined function.
@noinline spec_work(n) = n > typemax(Int) ? println(n) : nothing
function calls_unspecialized(g, args...)
    ci = first(only(Base.code_typed(g, typeof.(args); optimize = true)))
    return any(ci.code) do st
        st isa Expr && st.head === :invoke || return false
        x = st.args[1]
        mi = x isa Core.MethodInstance ? x : isdefined(x, :def) ? x.def : nothing
        mi isa Core.MethodInstance || return false
        return any(T -> T === Function, mi.specTypes.parameters)
    end
end
@testset "specialization on the function arguments" begin
    @testset "$(nameof(typeof(sched)))" for sched in (SerialScheduler(), DynamicScheduler(),
                                                      StaticScheduler(), GreedyScheduler())
        calls = Any[
            n -> tforeach(_ -> spec_work(n), 1:8; scheduler = sched),
            n -> treduce((a, b) -> (spec_work(n); a + b), 1:8; scheduler = sched),
            n -> tmapreduce(i -> (spec_work(n); i), +, 1:8; scheduler = sched),
            n -> tmap!(i -> (spec_work(n); i), zeros(Int, 8), 1:8; scheduler = sched),
        ]
        sched isa GreedyScheduler ||
            push!(calls, n -> tmap(i -> (spec_work(n); i), 1:8; scheduler = sched))
        for g in calls
            g(3)
            @test !calls_unspecialized(g, 3)
        end
    end
end
