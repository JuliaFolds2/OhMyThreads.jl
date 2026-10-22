@testset "task index" begin
    WithTaskIndex = OhMyThreads.WithTaskIndex
    N = 100
    nt = 4
    # expected task index of each element for chunked Static/DynamicScheduler
    chunkindex(n, nt) = [c for (c, inds) in enumerate(OhMyThreads.index_chunks(1:n; n = nt))
                         for _ in inds]

    @testset "$(sched)" for sched in (
        StaticScheduler, DynamicScheduler, GreedyScheduler, ChunkedGreedy)
        kwargs = sched === ChunkedGreedy ? (; ntasks = nt, nchunks = 3 * nt) :
                 (; ntasks = nt)
        scheduler = sched(; kwargs...)
        chunked = sched in (StaticScheduler, DynamicScheduler)

        # macro API
        idxs = zeros(Int, N)
        tids = zeros(UInt, N)
        @tasks for i in 1:N
            @set scheduler = scheduler
            @local idx = @task_index
            idxs[i] = idx
            tids[i] = OhMyThreads.Tools.taskid()
        end
        @test issubset(idxs, 1:nt)
        chunked && @test idxs == chunkindex(N, nt)
        # one-to-one correspondence between tasks and task indices
        @test length(unique(zip(tids, idxs))) == length(unique(tids)) ==
              length(unique(idxs))

        # functional API
        idxs .= 0
        tforeach(WithTaskIndex((idx, i) -> idxs[i] = idx), 1:N; scheduler)
        @test issubset(idxs, 1:nt)
        chunked && @test idxs == chunkindex(N, nt)
        idxs_red = tmapreduce(WithTaskIndex((idx, i) -> [idx]), vcat, 1:N; scheduler)
        @test issubset(idxs_red, 1:nt)
        chunked && @test idxs_red == chunkindex(N, nt)
        # multiple input arrays
        @test tmapreduce(WithTaskIndex((idx, x, y) -> idx in 1:nt && x == y), &,
            1:N, 1:N; scheduler)
    end

    @testset "@task_index" begin
        # in combination with other task local values and types
        res = @tasks for i in 1:8
            @set ntasks = nt
            @set collect = true
            @local begin
                x = Ref(0)
                idx::Int = @task_index
                y::Float64 = 10 * OhMyThreads.@task_index()
            end
            x[] += 1
            (idx, y, x[])
        end
        @test res == [(c, 10.0 * c, k) for c in 1:nt for k in 1:2]

        # the names of other task local values are not in scope in @task_index initializers
        let x = collect(1:nt), y = collect(10:10:(10 * nt))
            res = @tasks for i in 1:nt
                @set ntasks = nt
                @set collect = true
                @local begin
                    x = zeros(1)
                    a = x[@task_index]
                    b = y[@task_index]
                end
                (a, b)
            end
            @test res == [(c, 10c) for c in 1:nt]
        end

        # Task-index locals also read their own and each other's names from outer scope.
        let x = collect(1:nt), y = collect(10:10:(10 * nt))
            res = @tasks for i in 1:nt
                @set ntasks = nt
                @set collect = true
                @local begin
                    x::Float64 = x[@task_index]
                    y = x[@task_index] + y[@task_index]
                end
                (x, y)
            end
            @test res == [(Float64(c), 11c) for c in 1:nt]
            @test eltype(res) == Tuple{Float64, Int}
        end

        # Greedy workers retain mutable task locals across elements and chunks.
        for scheduler in (GreedyScheduler(; ntasks = nt),
            GreedyScheduler(; ntasks = nt, nchunks = 3 * nt))
            let counter = Threads.Atomic{Int}(0), values = zeros(Int, N),
                idxs = zeros(Int, N)
                @tasks for i in 1:N
                    @set scheduler = scheduler
                    @local state = (Threads.atomic_add!(counter, 1); (@task_index, Ref(0)))
                    idx, count = state
                    count[] += 1
                    idxs[i] = idx
                    values[i] = count[]
                end
                @test counter[] == nt
                for idx in unique(idxs)
                    counts = values[idxs .== idx]
                    @test sort(counts) == 1:length(counts)
                end
            end
        end

        # reducer
        @test @tasks(for i in 1:N
            @set ntasks = nt
            @set reducer = max
            @local idx = @task_index
            idx
        end) == nt

        # preallocated task-local buffers (#157)
        let buffers = [Ref(0) for _ in 1:nt], ids = zeros(UInt, N),
            tids = zeros(UInt, N)

            for _ in 1:3
                @tasks for i in 1:N
                    @set ntasks = nt
                    @local buffer = buffers[@task_index]
                    buffer[] += 1
                    ids[i] = objectid(buffer)
                    tids[i] = OhMyThreads.Tools.taskid()
                end
                # every task has its own buffer
                @test length(unique(zip(tids, ids))) == length(unique(tids)) ==
                      length(unique(ids)) == nt
            end
            @test sum(b -> b[], buffers) == 3 * N
        end

        # evaluated once per task, also if no tasks are spawned
        let counter = Threads.Atomic{Int}(0)
            count!(idx) = (Threads.atomic_add!(counter, 1); idx)
            @tasks for i in 1:N
                @set ntasks = nt
                @local idx = count!(@task_index)
            end
            @test counter[] == nt
            counter[] = 0
            @tasks for i in 1:N
                @set scheduler = SerialScheduler()
                @local idx = count!(@task_index)
            end
            @test counter[] == 1
        end

        # nested
        @test @tasks(for i in 1:N
            @set ntasks = nt
            @set reducer = (&)
            @local outer = @task_index
            inner = @tasks for j in 1:4
                @set ntasks = 2
                @set collect = true
                @local idx = @task_index
                (outer, idx)
            end
            inner == [(outer, 1), (outer, 1), (outer, 2), (outer, 2)]
        end)

        # type stability
        @test @inferred (() -> @tasks for i in 1:N
            @set ntasks = nt
            @set reducer = (+)
            @local idx = @task_index
            idx
        end)() == sum(chunkindex(N, nt))

        # wrong usage
        @test_throws "may only be used inside of a @local block" @macroexpand(@task_index)
        @test_throws "may only be used inside of a @local block" @macroexpand(@tasks(for i in 1:N
            x = @task_index
        end))
        @test_throws "may only be used inside of a @local block" @macroexpand(@tasks(for i in 1:N
            @set reducer = (a, b) -> a + @task_index
            i
        end))
        @test_throws "doesn't take any arguments" @macroexpand(@tasks(for i in 1:N
            @local x = @task_index 1
        end))
    end

    @testset "WithTaskIndex" begin
        f = WithTaskIndex((idx, _) -> idx)

        # tmap / tmap! / tcollect / @tasks with collect
        @test tmap(f, 1:8; ntasks = nt) == chunkindex(8, nt)
        @test tmap(f, Int, 1:8; ntasks = nt) == chunkindex(8, nt)
        @test tmap!(f, zeros(Int, 8), 1:8; ntasks = nt) == chunkindex(8, nt)
        @test tmap(WithTaskIndex((idx, x, y) -> (idx, x + y)), 1:8, 1:8; ntasks = nt) ==
              collect(zip(chunkindex(8, nt), 2:2:16))
        A = rand(4, 6)
        @test tmap(WithTaskIndex((idx, x) -> x), A; ntasks = nt) == A

        # no chunking: one task per element
        for scheduler in (DynamicScheduler(; chunking = false),
            StaticScheduler(; chunking = false))
            @test tmap(f, 11:17; scheduler) == 1:7
            @test tmapreduce(f, vcat, 11:17; scheduler) == 1:7
        end

        # chunks as input
        for scheduler in (DynamicScheduler(; chunking = false),
            StaticScheduler(; chunking = false))
            chnks = OhMyThreads.index_chunks(1:N; n = nt)
            @test tmap(f, chnks; scheduler) == 1:nt
            @test tmapreduce(f, vcat, chnks; scheduler) == 1:nt
        end
        @test tmap(WithTaskIndex((idx, (c, _)) -> c == idx),
            enumerate(OhMyThreads.index_chunks(1:N; n = nt))) == trues(nt)
        @test tmapreduce(WithTaskIndex((idx, (c, _)) -> c == idx), &,
            enumerate(OhMyThreads.index_chunks(1:N; n = nt)))

        # no tasks spawned: SerialScheduler, single chunk, empty input
        @test tmap(f, 1:5; scheduler = SerialScheduler()) == ones(Int, 5)
        @test tmapreduce(f, +, 1:5; scheduler = SerialScheduler()) == 5
        @test tmap!(f, zeros(Int, 5), 1:5; scheduler = SerialScheduler()) == ones(Int, 5)
        @test tforeach(f, 1:5; scheduler = SerialScheduler()) === nothing
        @test tmapreduce(f, +, 1:5; minchunksize = 100) == 5
        @test tmapreduce(f, +, 1:5; ntasks = 1) == 5
        @test tmap(f, Int[]; ntasks = nt) == Int[]

        # in combination with task local values
        let tlv = TaskLocalValue{Base.RefValue{Int}}(() -> Ref(0))
            g = WithTaskLocals((tlv,)) do (x,)
                WithTaskIndex((idx, _) -> (x[] += 1; (idx, x[])))
            end
            @test tmap(g, 1:8; ntasks = nt) == [(c, k) for c in 1:nt for k in 1:2]
            @test tmapreduce(g, vcat, 1:8; ntasks = nt) ==
                  [(c, k) for c in 1:nt for k in 1:2]
            # the other way around: task local values are looked up once per task
            h = WithTaskIndex(WithTaskLocals((tlv,)) do (x,)
                (idx, _) -> (x[] += 1; (idx, x[]))
            end)
            @test tmap(h, 1:8; ntasks = nt) == [(c, k) for c in 1:nt for k in 1:2]
            @test tmap(h, 1:4; scheduler = SerialScheduler()) == [(1, k) for k in 1:4]
        end

        # the task index is only passed by the parallel functions
        @test_throws "can't be called directly" f(1)
        @test promise_task_local(f, 3)(1) == 3
        @test promise_task_local(sin, 3) === sin

        # type stability
        @test @inferred(tmapreduce(f, +, 1:N; ntasks = nt)) == sum(chunkindex(N, nt))
        @test @inferred(tmap(f, Int, 1:N; ntasks = nt)) == chunkindex(N, nt)
    end
end;
