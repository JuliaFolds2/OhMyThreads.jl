using Test, OhMyThreads
using OhMyThreads: TaskLocalValue, WithTaskLocals, @fetch, promise_task_local
using OhMyThreads: Consecutive, RoundRobin
using OhMyThreads.Experimental: @barrier
using OhMyThreads.Implementation: BoxedVariableError

@info "Testing with $(Threads.nthreads(:default)),$(Threads.nthreads(:interactive)) threads."

include("Aqua.jl")

sets_to_test = [(~ = isapprox, f = sin ∘ *, op = +,
                    itrs = (rand(ComplexF64, 10, 10), rand(-10:10, 10, 10)),
                    init = complex(0.0))
                (~ = isapprox, f = cos, op = max, itrs = (1:100000,), init = 0.0)
                (~ = (==), f = round, op = vcat, itrs = (randn(1000),), init = Float64[])
                (~ = (==), f = last, op = *,
                    itrs = ([1 => "a", 2 => "b", 3 => "c", 4 => "d", 5 => "e"],),
                    init = "")]

ChunkedGreedy(; kwargs...) = GreedyScheduler(; kwargs...)

@testset "Basics" begin
    for (; ~, f, op, itrs, init) in sets_to_test
        @testset "f=$f, op=$op, itrs::$(typeof(itrs))" begin
            @testset for sched in (
                StaticScheduler, DynamicScheduler, GreedyScheduler,
                DynamicScheduler{OhMyThreads.Schedulers.NoChunking},
                SerialScheduler, ChunkedGreedy)
                @testset for split in (Consecutive(), RoundRobin(), :consecutive, :roundrobin)
                    for nchunks in (1, 2, 6)
                        for minchunksize ∈ (nothing, 1, 3)
                            if sched == GreedyScheduler
                                scheduler = sched(; ntasks = nchunks, minchunksize)
                            elseif sched == DynamicScheduler{OhMyThreads.Schedulers.NoChunking}
                                scheduler = DynamicScheduler(; chunking = false)
                            elseif sched == SerialScheduler
                                scheduler = SerialScheduler(; nchunks)
                            else
                                scheduler = sched(; nchunks, split, minchunksize)
                            end
                            kwargs = (; scheduler)
                            if (split in (RoundRobin(), :roundrobin) ||
                                sched ∈ (GreedyScheduler, ChunkedGreedy)) || op ∉ (vcat, *)
                                # scatter and greedy only works for commutative operators!
                            else
                                mapreduce_f_op_itr = mapreduce(f, op, itrs...)
                                @test tmapreduce(f, op, itrs...; init, kwargs...) ~ mapreduce_f_op_itr
                                @test treducemap(op, f, itrs...; init, kwargs...) ~ mapreduce_f_op_itr
                                @test treduce(op, f.(itrs...); init, kwargs...) ~ mapreduce_f_op_itr
                            end

                            split in (RoundRobin(), :roundrobin) && continue
                            map_f_itr = map(f, itrs...)
                            @test all(tmap(f, Any, itrs...; kwargs...) .~ map_f_itr)
                            @test all(tcollect(Any, (f(x...) for x in collect(zip(itrs...))); kwargs...) .~ map_f_itr)
                            @test all(tcollect(Any, f.(itrs...); kwargs...) .~ map_f_itr)

                            RT = Core.Compiler.return_type(f, Tuple{eltype.(itrs)...})

                            @test tmap(f, RT, itrs...; kwargs...) ~ map_f_itr
                            @test tcollect(RT, (f(x...) for x in collect(zip(itrs...))); kwargs...) ~ map_f_itr
                            @test tcollect(RT, f.(itrs...); kwargs...) ~ map_f_itr

                            if sched ∉ (GreedyScheduler, ChunkedGreedy)
                                @test tmap(f, itrs...; kwargs...) ~ map_f_itr
                                @test tcollect((f(x...) for x in collect(zip(itrs...))); kwargs...) ~ map_f_itr
                                @test tcollect(f.(itrs...); kwargs...) ~ map_f_itr
                            end
                        end
                    end
                end
            end
        end
    end
end;

@testset "ChunkSplitters.Chunk" begin
    x = rand(100)
    chnks = OhMyThreads.index_chunks(x; n = Threads.nthreads())
    for scheduler in (
        DynamicScheduler(),
        DynamicScheduler(; chunking = false),
        StaticScheduler(; chunking = false))
        @testset "$scheduler" begin
            @test tmap(x -> sin.(x), chnks; scheduler) ≈ map(x -> sin.(x), chnks)
            @test tmapreduce(x -> sin.(x), vcat, chnks; scheduler) ≈
                  mapreduce(x -> sin.(x), vcat, chnks)
            @test tcollect(chnks; scheduler) == collect(chnks)
            @test treduce(vcat, chnks; scheduler) == reduce(vcat, chnks)
            @test isnothing(tforeach(x -> sin.(x), chnks; scheduler))
        end
    end

    # enumerate(chunks)
    data = 1:100
    @test tmapreduce(+, enumerate(OhMyThreads.index_chunks(data; n=5)); chunking=false) do (i, idcs)
        [i, sum(@view(data[idcs]))]
    end == [sum(1:5), sum(data)]
    @test tmapreduce(+, enumerate(OhMyThreads.index_chunks(data; size=5)); chunking=false) do (i, idcs)
        [i, sum(@view(data[idcs]))]
    end == [sum(1:20), sum(data)]
    @test tmap(enumerate(OhMyThreads.index_chunks(data; n=5)); chunking=false) do (i, idcs)
        [i, idcs]
    end == [[1, 1:20], [2, 21:40], [3, 41:60], [4, 61:80], [5, 81:100]]
end;

@testset "macro API" begin
    # basic
    @test @tasks(for i in 1:3
        i
    end) |> isnothing

    # reduction
    @test @tasks(for i in 1:3
        @set reducer = (+)
        i
    end) == 6

    # scheduler settings
    for sched in (StaticScheduler(), DynamicScheduler(), GreedyScheduler())
        @test @tasks(for i in 1:3
            @set scheduler = sched
            i
        end) |> isnothing
    end
    # scheduler settings as symbols
    @test @tasks(for i in 1:3
        @set scheduler = :static
        i
    end) |> isnothing
    @test @tasks(for i in 1:3
        @set scheduler = :dynamic
        i
    end) |> isnothing
    @test @tasks(for i in 1:3
        @set scheduler = :greedy
        i
    end) |> isnothing

    # @set begin ... end
    @test @tasks(for i in 1:10
        @set begin
            scheduler = StaticScheduler()
            reducer = (+)
        end
        i
    end) == 55
    # multiple @set
    @test @tasks(for i in 1:10
        @set scheduler = StaticScheduler()
        i
        @set reducer = (+)
    end) == 55
    # @set init
    @test @tasks(for i in 1:10
        @set begin
            reducer = (+)
            init = 0.0
        end
        i
    end) === 55.0
    @test @tasks(for i in 1:10
        @set begin
            reducer = (+)
            init = 0.0 * im
        end
        i
    end) === (55.0 + 0.0im)

    # top-level "kwargs"
    @test @tasks(for i in 1:3
        @set scheduler = :static
        @set ntasks = 1
        i
    end) |> isnothing
    @test @tasks(for i in 1:3
        @set scheduler = :static
        @set nchunks = 2
        i
    end) |> isnothing
    @test @tasks(for i in 1:3
        @set scheduler = :dynamic
        @set chunksize = 2
        i
    end) |> isnothing
    @test @tasks(for i in 1:3
        @set scheduler = :dynamic
        @set chunking = false
        i
    end) |> isnothing
    @test @tasks(for i in 1:4
        @set minchunksize=2
        i
    end) |> isnothing
    @test_throws ArgumentError @tasks(for i in 1:3
        @set scheduler = DynamicScheduler()
        @set chunking = false
        i
    end)
    @test_throws MethodError @tasks(for i in 1:3
        @set scheduler = :dynamic
        @set asd = 123
        i
    end)

    # TaskLocalValue
    ntd = 2 * Threads.nthreads()
    ptrs = Vector{Ptr{Nothing}}(undef, ntd)
    tids = Vector{UInt64}(undef, ntd)
    tid() = OhMyThreads.Tools.taskid()
    @test @tasks(for i in 1:ntd
        @local C::Vector{Float64} = rand(3)
        @set scheduler = :static
        ptrs[i] = pointer_from_objref(C)
        tids[i] = tid()
    end) |> isnothing
    # check that different iterations of a task
    # have access to the same C (same pointer)
    for t in unique(tids)
        @test allequal(ptrs[findall(==(t), tids)])
    end
    # TaskLocalValue (another fundamental check)
    @test @tasks(for i in 1:ntd
        @local x::Ref{Int64} = Ref(0)
        @set reducer = (+)
        @set scheduler = :static
        x[] += 1
        x[]
    end) == 1.5 * ntd # if a new x would be allocated per iteration, we'd get ntd here.
    # TaskLocalValue (begin ... end block), inferred TLV type
    @test @inferred (() -> @tasks for i in 1:10
        @local begin
            C = fill(4, 3, 3)
            x = fill(5.0, 3)
        end
        @set reducer = (+)
        sum(C * x)
    end)() == 1800

    # hygiene / escaping
    var = 3
    sched = StaticScheduler()
    sched_sym = :static
    data = rand(10)
    red = (a, b) -> a + b
    n = 2
    @test @tasks(for d in data
        @set scheduler = sched
        @set reducer = red
        var * d
    end) ≈ var * sum(data)
    @test @tasks(for d in data
        @set scheduler = sched_sym
        @set ntasks = n
        @set reducer = red
        var * d
    end) ≈ var * sum(data)

    struct SingleInt
        x::Int
    end
    @test @tasks(for _ in 1:10
        @local C = SingleInt(var)
        @set reducer = +
        C.x
    end) == 10 * var

    # enumerate(chunks)
    let data = collect(1:100)
        @test @tasks(for (i, idcs) in enumerate(OhMyThreads.index_chunks(data; n=5))
                         @set reducer = +
                             @set chunking = false
                         [i, sum(@view(data[idcs]))]
                     end) == [sum(1:5), sum(data)]
        @test @tasks(for (i, idcs) in enumerate(OhMyThreads.index_chunks(data; size=5))
                         @set reducer = +
                             [i, sum(@view(data[idcs]))]
                     end) == [sum(1:20), sum(data)]
        @test @tasks(for (i, idcs) in enumerate(OhMyThreads.index_chunks(1:100; n=5))
                         @set chunking=false
                         @set collect=true
                         [i, idcs]
                     end) == [[1, 1:20], [2, 21:40], [3, 41:60], [4, 61:80], [5, 81:100]]
    end
end;

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

@testset "WithTaskLocals" begin
    let x = TaskLocalValue{Base.RefValue{Int}}(() -> Ref{Int}(0)),
        y = TaskLocalValue{Base.RefValue{Int}}(() -> Ref{Int}(0))
        # Equivalent to
        # function f()
        #    x[][] += 1
        #    x[][] += 1
        #    x[], y[]
        # end
        f = WithTaskLocals((x, y)) do (x, y)
            function ()
                x[] += 1
                y[] += 1
                x[], y[]
            end
        end
        # Make sure we can call `f` like a regular function
        @test f() == (1, 1)
        @test f() == (2, 2)
        @test @fetch(f()) == (1, 1)
        # Acceptable use of promise_task_local
        @test @fetch(promise_task_local(f)()) == (1, 1)
        # Acceptable use of promise_task_local
        @test promise_task_local(f)() == (3, 3)
        # Acceptable use of promise_task_local
        @test @fetch(promise_task_local(f)()) == (1, 1)
        # Acceptable use of promise_task_local
        g() = @fetch((promise_task_local(f)(); promise_task_local(f)(); f()))
        @test g() == (3, 3)
        @test g() == (3, 3)

        h = promise_task_local(f)
        # Unacceptable use of `promise_task_local`
        # This is essentially testing that if you use `promise_task_local`, then pass that to another task,
        # you could get data races, since we here have a different thread writing to another thread's value.
        @test @fetch(h()) == (4, 4)
        @test @fetch(h()) == (5, 5)
    end
end;

@testset "chunking mode + chunksize option" begin
    @test OhMyThreads.Schedulers.chunking_mode(SerialScheduler()) ==
          OhMyThreads.Schedulers.NoChunking
    for sched in (DynamicScheduler, StaticScheduler, GreedyScheduler)
        @test sched() isa sched
        @test sched(; chunksize = 2) isa sched

        @test OhMyThreads.Schedulers.chunking_mode(sched(; chunksize = 2)) ==
              OhMyThreads.Schedulers.FixedSize
        @test OhMyThreads.Schedulers.chunking_mode(sched(; nchunks = 2)) ==
              OhMyThreads.Schedulers.FixedCount
        @test OhMyThreads.Schedulers.chunking_mode(sched(; chunking = false)) ==
              OhMyThreads.Schedulers.NoChunking
        if sched != GreedyScheduler
            # For (Dynamic|Static)Scheduler `chunking = false` disables all chunking
            # arguments
            @test OhMyThreads.Schedulers.chunking_mode(sched(;
                nchunks = 2, chunksize = 4, chunking = false)) ==
                  OhMyThreads.Schedulers.NoChunking
            @test OhMyThreads.Schedulers.chunking_mode(sched(;
                nchunks = nothing, chunksize = nothing, split = :whatever, chunking = false)) ==
                  OhMyThreads.Schedulers.NoChunking
            @test OhMyThreads.Schedulers.chunking_enabled(sched(;
                nchunks = nothing, chunksize = nothing, chunking = false)) == false
            @test OhMyThreads.Schedulers.chunking_enabled(sched(;
                nchunks = 2, chunksize = 4, chunking = false)) == false
        else
            # For GreedyScheduler `nchunks` or `chunksize` overrides `chunking = false`
            @test OhMyThreads.Schedulers.chunking_mode(sched(;
                nchunks = 2, chunking = false)) ==
                  OhMyThreads.Schedulers.FixedCount
            @test OhMyThreads.Schedulers.chunking_mode(sched(;
                chunksize = 2, chunking = false)) ==
                  OhMyThreads.Schedulers.FixedSize
            @test OhMyThreads.Schedulers.chunking_enabled(sched(;
                nchunks = 2, chunking = false)) == true
            @test OhMyThreads.Schedulers.chunking_enabled(sched(;
                chunksize = 4, chunking = false)) == true
        end
        @test OhMyThreads.Schedulers.chunking_enabled(sched(; chunksize = 2)) == true
        @test OhMyThreads.Schedulers.chunking_enabled(sched(; nchunks = 2)) == true
        @test_throws ArgumentError sched(; nchunks = 2, chunksize = 3)
        @test_throws ArgumentError sched(; nchunks = 2, split = :whatever)

        let scheduler = sched(; chunksize = 2, split = :batch)
            @test tmapreduce(sin, +, 1:10; scheduler, init=0.0) ≈ mapreduce(sin, +, 1:10)
            @test treduce(+, 1:10; scheduler, init=0.0) ≈ reduce(+, 1:10)
            @test tmap(sin, Float64, 1:10; scheduler) ≈ map(sin, 1:10)
            @test isnothing(tforeach(sin, 1:10; scheduler))
        end
    end
end;

@testset "top-level kwargs" begin
    res_tmr = mapreduce(sin, +, 1:10000)

    # scheduler not given
    @test tmapreduce(sin, +, 1:10000; ntasks = 2) ≈ res_tmr
    @test tmapreduce(sin, +, 1:10000; nchunks = 2) ≈ res_tmr
    @test tmapreduce(sin, +, 1:10000; split = RoundRobin()) ≈ res_tmr
    @test tmapreduce(sin, +, 1:10000; chunksize = 2) ≈ res_tmr
    @test tmapreduce(sin, +, 1:10000; chunking = false) ≈ res_tmr
    @test tmapreduce(sin, +, 1:10000; minchunksize=10) ≈ res_tmr
    @test tmapreduce(sin, +, 1:10; minchunksize=10) == mapreduce(sin, +, 1:10)

    # scheduler isa Scheduler
    @test tmapreduce(sin, +, 1:10000; scheduler = StaticScheduler()) ≈ res_tmr
    @test_throws ArgumentError tmapreduce(
        sin, +, 1:10000; ntasks = 2, scheduler = DynamicScheduler())
    @test_throws ArgumentError tmapreduce(
        sin, +, 1:10000; chunksize = 2, scheduler = DynamicScheduler())
    @test_throws ArgumentError tmapreduce(
        sin, +, 1:10000; split = RoundRobin(), scheduler = StaticScheduler())
    @test_throws ArgumentError tmapreduce(
        sin, +, 1:10000; ntasks = 3, scheduler = SerialScheduler())

    # scheduler isa Symbol
    for s in (:dynamic, :static, :serial, :greedy)
        @test tmapreduce(sin, +, 1:10000; scheduler = s, init = 0.0) ≈ res_tmr
    end
    for s in (:dynamic, :static, :greedy)
        @test tmapreduce(sin, +, 1:10000; ntasks = 2, scheduler = s, init = 0.0) ≈ res_tmr
    end
    for s in (:dynamic, :static)
        @test tmapreduce(sin, +, 1:10000; chunksize = 2, scheduler = s) ≈ res_tmr
        @test tmapreduce(sin, +, 1:10000; chunking = false, scheduler = s) ≈ res_tmr
        @test tmapreduce(sin, +, 1:10000; nchunks = 3, scheduler = s) ≈ res_tmr
        @test tmapreduce(sin, +, 1:10000; ntasks = 3, scheduler = s) ≈ res_tmr
        @test_throws ArgumentError tmapreduce(
            sin, +, 1:10000; ntasks = 3, nchunks = 2, scheduler = s)≈res_tmr
    end
    @test_throws ArgumentError tmapreduce(sin, +, 1:10000; scheduler = :whatever)
    @test_throws ArgumentError tmapreduce(
        sin, +, 1:10000; threadpool = :whatever, chunking = false)

    # scheduler isa Val
    for (s, S) in ((:dynamic, DynamicScheduler), (:static, StaticScheduler),
        (:serial, SerialScheduler), (:greedy, GreedyScheduler))
        @test tmapreduce(sin, +, 1:10000; scheduler = Val(s), init = 0.0) ≈ res_tmr
        @test OhMyThreads.Implementation._scheduler_from_userinput(Val(s)) isa S
    end
    @test tmapreduce(sin, +, 1:10000; ntasks = 2, scheduler = Val(:static)) ≈ res_tmr
    @test_throws ArgumentError tmapreduce(sin, +, 1:10000; scheduler = Val(:whatever))
end;

@testset "SizeUnknown iterators (greedy)" begin
    itr = Iterators.filter(isodd, 1:10)
    @test tmapreduce(identity, +, itr; scheduler = :greedy, init = 0) == 25
    @test tmapreduce(x -> x^2, +, itr; scheduler = :greedy, init = 0) ==
          mapreduce(x -> x^2, +, itr)
    @test tforeach(identity, itr; scheduler = :greedy) |> isnothing
    # chunking requires a known size
    @test_throws ArgumentError tmapreduce(
        identity, +, itr; scheduler = GreedyScheduler(; chunking = true), init = 0)
    # other schedulers
    for scheduler in (:dynamic, :static, DynamicScheduler(; chunking = false),
        StaticScheduler(; chunking = false))
        @test_throws "only supported by the `GreedyScheduler`" tmapreduce(
            identity, +, itr; scheduler)
        @test_throws "only supported by the `GreedyScheduler`" tforeach(
            identity, itr; scheduler)
    end
    @test tmapreduce(identity, +, itr; scheduler = :serial) == 25
    # multiple inputs
    for args in ((itr, [1, 2, 3]), ([1, 2, 3], itr))
        @test_throws "can't be combined with other inputs" tmapreduce(
            +, +, args...; scheduler = :greedy)
    end
    # type stability
    @test @inferred(tmapreduce(identity, +, itr; scheduler = GreedyScheduler(), init = 0)) == 25
end;

# An iterator of unknown size that records the task iterating it
mutable struct TaskRecordingIterator
    task::Union{Nothing, Task}
end
Base.IteratorSize(::Type{TaskRecordingIterator}) = Base.SizeUnknown()
Base.eltype(::Type{TaskRecordingIterator}) = Int
function Base.iterate(it::TaskRecordingIterator, i = 1)
    it.task = current_task()
    return i <= 1000 ? (i, i + 1) : nothing
end

@testset "GreedyScheduler: producer terminates if all consumers fail" begin
    it = TaskRecordingIterator(nothing)
    @test_throws TaskFailedException tforeach(x -> error("boom"), it; scheduler = :greedy)
    t0 = time()
    while !istaskdone(it.task) && time() - t0 < 10
        sleep(0.01)
    end
    @test istaskdone(it.task)
end;

# Models an array with a mutable read cache or a shared seek/read handle.
struct SerialReadVector <: AbstractVector{Int}
    reading::Threads.Atomic{Bool}
end
Base.size(::SerialReadVector) = (20,)
Base.IndexStyle(::Type{SerialReadVector}) = IndexLinear()
function Base.getindex(A::SerialReadVector, i::Int)
    Threads.atomic_cas!(A.reading, false, true) && error("concurrent getindex")
    try
        # Allow another worker to attempt a read, including with only one thread.
        sleep(0.001)
        return i
    finally
        Threads.atomic_xchg!(A.reading, false)
    end
end

@testset "GreedyScheduler: custom arrays are read by a single producer" begin
    A = SerialReadVector(Threads.Atomic{Bool}(false))
    scheduler = GreedyScheduler(; ntasks = 4)
    @test @inferred(treduce(+, A; scheduler)) == sum(1:20)
    @test treduce(+, view(A, :); scheduler) == sum(1:20)
    # Every input must support concurrent reads to use the fast path.
    @test tmapreduce(+, +, A, 1:20; scheduler) == 2sum(1:20)
    @test tmapreduce(+, +, 1:20, A; scheduler) == 2sum(1:20)
end;

@testset "GreedyScheduler: type stability" begin
    for scheduler in (GreedyScheduler(), GreedyScheduler(; chunking = true))
        @test @inferred(tmapreduce(sin, +, 1:100; scheduler)) ≈ mapreduce(sin, +, 1:100)
        @test @inferred(treduce(+, 1:100; scheduler)) == sum(1:100)
    end
end;

@testset "number of chunks for chunksize" begin
    # 1:11 with chunksize=6 is split into 2 chunks ([1:6, 7:11]) and should parallelize
    @test OhMyThreads.Implementation.has_multiple_chunks(
        DynamicScheduler(; chunksize = 6), 1:11)
    @test !OhMyThreads.Implementation.has_multiple_chunks(
        DynamicScheduler(; chunksize = 6), 1:6)
    @test treduce(+, 1:11; chunksize = 6) == sum(1:11)
    @test treduce(+, 1:6; chunksize = 6) == sum(1:6)
    # tmap: one task per chunk
    taskid() = OhMyThreads.Tools.taskid()
    for scheduler in (DynamicScheduler(; chunksize = 6), StaticScheduler(; chunksize = 6))
        @test length(unique(tmap(_ -> taskid(), 1:11; scheduler))) == 2
        @test length(unique(tmap(_ -> taskid(), 1:100; scheduler))) == 17
        @test tmap(OhMyThreads.WithTaskIndex((c, _) -> c), 1:11; scheduler) ==
              [fill(1, 6); fill(2, 5)]
    end
    @test length(unique(tmap(_ -> taskid(), 1:100; ntasks = 4, minchunksize = 10))) == 4
    @test tmap(sin, 1:100; chunksize = 6) == map(sin, 1:100)
end;

@testset "empty collections" begin
    @static if VERSION < v"1.11.0-"
        err = MethodError
    else
        err = ArgumentError
    end
    for empty_coll in (11:9, Float64[])
        for f in (sin, x -> im * x, identity)
            for op in (+, *, min)
                # mapreduce
                for init in (0.0, 0, 0.0 * im, 0.0f0)
                    @test tmapreduce(f, op, empty_coll; init) == init
                end
                # foreach
                @test tforeach(f, empty_coll) |> isnothing
                # reduce
                if op != min
                    @test treduce(op, empty_coll) == reduce(op, empty_coll)
                else
                    @test_throws err treduce(op, empty_coll)
                end
                # map
                @test tmap(f, empty_coll) == map(f, empty_coll)
                @test tmap(f, empty_coll; ntasks = 4) == map(f, empty_coll)
                @test tmap(f, empty_coll; scheduler = :static, chunksize = 2) ==
                      map(f, empty_coll)
                # collect
                @test tcollect(empty_coll) == collect(empty_coll)
            end
        end
    end
end;

@testset "tmap without chunking" begin
    for sched in (DynamicScheduler, StaticScheduler)
        scheduler = sched(; chunking = false)
        # elements that are not valid indices
        @test tmap(x -> 2x, [10, 20, 30]; scheduler) == [20, 40, 60]
        @test tmap(+, [10, 20, 30], [1.5, 2.5, 3.5]; scheduler) == [11.5, 22.5, 33.5]
        A = rand(3, 4)
        @test tmap(sin, A; scheduler) == map(sin, A)
    end
end;

@testset "tmap with SerialScheduler and kwargs" begin
    @test tmap(sin, 1:10; scheduler = :serial, ntasks = 2) == map(sin, 1:10)
end;

# for testing @one_by_one region
mutable struct SingleAccessOnly
    in_use::Bool
    const lck::ReentrantLock
    SingleAccessOnly() = new(false, ReentrantLock())
end
function acquire(f, o::SingleAccessOnly)
    lock(o.lck) do
        o.in_use && throw(ErrorException("Already in use!"))
        o.in_use = true
    end
    try
        f()
    finally
        lock(o.lck) do
            !o.in_use && throw(ErrorException("Conflict!"))
            o.in_use = false
        end
    end
end

@testset "regions" begin
    @testset "@one_by_one" begin
        sao = SingleAccessOnly()

        try
            @tasks for i in 1:10
                @set ntasks = 10
                @one_by_one begin
                    acquire(sao) do
                        sleep(0.01)
                    end
                end
            end
        catch ErrorException
            @test false
        else
            @test true
        end


        # test escaping
        let
            x = Ref(0)
            y = Ref(0)
            @tasks for i in 1:10
                @set ntasks = 10

                y[] += 1 # not safe (race condition)
                @one_by_one begin
                    x[] += 1 # parallel-safe because inside of one_by_one region
                    acquire(sao) do
                        sleep(0.01)
                    end
                end
            end
            @test x[] == 10

        end

        test_f = () -> begin
            x = Ref(0)
            y = Ref(0)
            @tasks for i in 1:10
                @set ntasks = 10

                y[] += 1 # not safe (race condition)
                @one_by_one begin
                    x[] += 1 # parallel-safe because inside of one_by_one region
                    acquire(sao) do
                        sleep(0.01)
                    end
                end
            end
            return x[]
        end
        @test test_f() == 10
    end

    @testset "@only_one" begin
        let
            x = Ref(0)
            y = Ref(0)
            try
                @tasks for i in 1:10
                    @set ntasks = 10

                    y[] += 1 # not safe (race condition)
                    @only_one begin
                        x[] += 1 # parallel-safe because only a single task will execute this
                    end
                end
                @test x[] == 1 # only a single task should have incremented x
            catch ErrorException
                @test false
            end
        end

        let
            x = Ref(0)
            y = Ref(0)
            try
                @tasks for i in 1:10
                    @set ntasks = 2

                    y[] += 1 # not safe (race condition)
                    @only_one begin
                        x[] += 1 # parallel-safe because only a single task will execute this
                    end
                end
                @test x[] == 5 # a single task should have incremented x 5 times
            catch ErrorException
                @test false
            end
        end

        test_f = () -> begin
            x = Ref(0)
            y = Ref(0)
            @tasks for i in 1:10
                @set ntasks = 2

                y[] += 1 # not safe (race condition)
                @only_one begin
                    x[] += 1 # parallel-safe because only a single task will execute this
                end
            end
            return x[]
        end
        @test test_f() == 5
    end

    @testset "@only_one + @one_by_one" begin
        x = Ref(0)
        y = Ref(0)
        try
            @tasks for i in 1:10
                @set ntasks = 10

                @only_one begin
                    x[] += 1 # parallel-safe
                end

                @one_by_one begin
                    y[] += 1 # parallel-safe
                end
            end
            @test x[] == 1 && y[] == 10
        catch ErrorException
            @test false
        end
    end
end;

@testset "@barrier" begin
    @test (@tasks for i in 1:20
        @set ntasks = 20
        @barrier
    end) |> isnothing

    @test try
        @macroexpand @tasks for i in 1:20
            @barrier
        end
        false
    catch
        true
    end

    @test try
        x = Threads.Atomic{Int64}(0)
        y = Threads.Atomic{Int64}(0)
        @tasks for i in 1:20
            @set ntasks = 20

            Threads.atomic_add!(x, 1)
            @barrier
            if x[] < 20 && y[] > 0 # x hasn't reached 20 yet and y is already > 0
                error("shouldn't happen")
            end
            Threads.atomic_add!(y, 1)
        end
        true
    catch ErrorException
        false
    end

    @test try
        x = Threads.Atomic{Int64}(0)
        y = Threads.Atomic{Int64}(0)
        @tasks for i in 1:20
            @set ntasks = 20

            Threads.atomic_add!(x, 1)
            @barrier
            Threads.atomic_add!(x, 1)
            @barrier
            if x[] < 40 && y[] > 0 # x hasn't reached 20 yet and y is already > 0
                error("shouldn't happen")
            end
            Threads.atomic_add!(y, 1)
        end
        true
    catch ErrorException
        false
    end
end

@testset "verbose special macro usage" begin
    # OhMyThreads.@set
    @test @tasks(for i in 1:3
        OhMyThreads.@set reducer = (+)
        i
    end) == 6
    @test @tasks(for i in 1:3
        OhMyThreads.@set begin
            reducer = (+)
        end
        i
    end) == 6
    # OhMyThreads.@local
    ntd = 2 * Threads.nthreads()
    @test @tasks(for i in 1:ntd
        OhMyThreads.@local x::Ref{Int64} = Ref(0)
        OhMyThreads.@set begin
            reducer = (+)
            scheduler = :static
        end
        x[] += 1
        x[]
    end) == @tasks(for i in 1:ntd
        @local x::Ref{Int64} = Ref(0)
        @set begin
            reducer = (+)
            scheduler = :static
        end
        x[] += 1
        x[]
    end)
    # OhMyThreads.@only_one
    let
        x = Ref(0)
        y = Ref(0)
        try
            @tasks for i in 1:10
                OhMyThreads.@set ntasks = 10

                y[] += 1 # not safe (race condition)
                OhMyThreads.@only_one begin
                    x[] += 1 # parallel-safe because only a single task will execute this
                end
            end
            @test x[] == 1 # only a single task should have incremented x
        catch ErrorException
            @test false
        end
    end
    # OhMyThreads.@one_by_one
    test_f = () -> begin
        sao = SingleAccessOnly()
        x = Ref(0)
        y = Ref(0)
        @tasks for i in 1:10
            OhMyThreads.@set ntasks = 10

            y[] += 1 # not safe (race condition)
            OhMyThreads.@one_by_one begin
                x[] += 1 # parallel-safe because inside of one_by_one region
                acquire(sao) do
                    sleep(0.01)
                end
            end
        end
        return x[]
    end
    @test test_f() == 10
end

@testset "show schedulers" begin
    nt = Threads.nthreads(:default)

    @test repr("text/plain", DynamicScheduler()) ==
          """
          DynamicScheduler
          ├ Chunking: fixed count ($nt), split :consecutive
          └ Threadpool: default"""

    @test repr(
        "text/plain", DynamicScheduler(; chunking = false, threadpool = :interactive)) ==
          """
          DynamicScheduler
          ├ Chunking: none
          └ Threadpool: interactive"""

    @test repr("text/plain", StaticScheduler()) ==
          """StaticScheduler
          ├ Chunking: fixed count ($nt), split :consecutive
          └ Threadpool: default"""

    @test repr("text/plain", StaticScheduler(; chunksize = 2, split = :scatter)) ==
          """
          StaticScheduler
          ├ Chunking: fixed size (2), split :roundrobin
          └ Threadpool: default"""

    @test repr("text/plain", GreedyScheduler(; chunking = true)) ==
          """
         GreedyScheduler
         ├ Num. tasks: $nt
         ├ Chunking: fixed count ($(10 * nt)), split :roundrobin
         └ Threadpool: default"""
end

if Threads.nthreads() > 1
    @testset "Boxing detection and error" begin
        let
            f1() = tmap(1:10) do i
                A = i
                sleep(rand()/10)
                A
            end
            f2() = tmap(1:10) do i
                local A = i
                sleep(rand()/10)
                A
            end

            @test f1() == 1:10
            @test f2() == 1:10
        end

        let
            f1() = tmap(1:10) do i
                A = i
                sleep(rand()/10)
                A
            end
            f2() = tmap(1:10) do i
                local A = i
                sleep(rand()/10)
                A
            end

            @test_throws BoxedVariableError f1()
            @test f2() == 1:10

            A = 1 # Cause spooky action-at-a-distance by making A outer-local to the whole let block!
        end

        let
            A = 1
            f1() = tmap(1:10) do i
                A = 1
            end
            @test_throws BoxedVariableError f1() == ones(10) # Throws even though the redefinition is 'harmless'

            @allow_boxed_captures begin
                f2() = tmap(1:10) do i
                    A = 1
                end
                @test f2() == ones(10)
            end

            # Can nest allow and disallow because they're scoped values!
            function f3()
                @disallow_boxed_captures begin
                    tmap(1:10) do i
                    A = 1
                    end
                end
            end
            @allow_boxed_captures begin
                @test_throws BoxedVariableError f3() == ones(10)
            end
        end
        @testset "@localize" begin
            A = 1
            if false
                A = 2
            end
            ## This stops A from being boxed!
            v = @localize A tmap(1:2) do _
                A
            end
            @test v == [1, 1]
        end
    end
end

# Todo way more testing, and easier tests to deal with

include("ProgressMeterExt.jl")
