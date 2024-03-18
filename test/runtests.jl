using Test, OhMyThreads
using OhMyThreads: TaskLocalValue, WithTaskLocals, @fetch, promise_task_local

sets_to_test = [(~ = isapprox, f = sin ∘ *, op = +,
                    itrs = (rand(ComplexF64, 10, 10), rand(-10:10, 10, 10)),
                    init = complex(0.0))
                (~ = isapprox, f = cos, op = max, itrs = (1:100000,), init = 0.0)
                (~ = (==), f = round, op = vcat, itrs = (randn(1000),), init = Float64[])
                (~ = (==), f = last, op = *,
                    itrs = ([1 => "a", 2 => "b", 3 => "c", 4 => "d", 5 => "e"],),
                    init = "")]

ChunkedGreedy(;kwargs...) = GreedyScheduler(;kwargs...)

@testset "Basics" begin
    for (; ~, f, op, itrs, init) in sets_to_test
        @testset "f=$f, op=$op, itrs::$(typeof(itrs))" begin
            @testset for sched in (
                StaticScheduler, DynamicScheduler, GreedyScheduler, DynamicScheduler{OhMyThreads.Schedulers.NoChunking}, SerialScheduler, ChunkedGreedy)
                @testset for split in (:batch, :scatter)
                    for nchunks in (1, 2, 6)
                        if sched == GreedyScheduler
                            scheduler = sched(; ntasks = nchunks)
                        elseif sched == DynamicScheduler{OhMyThreads.Schedulers.NoChunking}
                            scheduler = DynamicScheduler(; chunking=false)
                        elseif sched == SerialScheduler
                            scheduler = SerialScheduler()
                        else
                            scheduler = sched(; nchunks, split)
                        end

                        kwargs = (; scheduler)
                        if (split == :scatter || sched ∈ (GreedyScheduler, ChunkedGreedy)) || op ∉ (vcat, *)
                            # scatter and greedy only works for commutative operators!
                        else
                            mapreduce_f_op_itr = mapreduce(f, op, itrs...)
                            @test tmapreduce(f, op, itrs...; init, kwargs...) ~ mapreduce_f_op_itr
                            @test treducemap(op, f, itrs...; init, kwargs...) ~ mapreduce_f_op_itr
                            @test treduce(op, f.(itrs...); init, kwargs...) ~ mapreduce_f_op_itr
                        end

                        split == :scatter && continue
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
end;

@testset "ChunkSplitters.Chunk" begin
    x = rand(100)
    chnks = OhMyThreads.chunks(x; n = Threads.nthreads())
    for scheduler in (DynamicScheduler(; chunking=false), StaticScheduler(; chunking=false))
        @testset "$scheduler" begin
            @test tmap(x -> sin.(x), chnks; scheduler) ≈ map(x -> sin.(x), chnks)
            @test tmapreduce(x -> sin.(x), vcat, chnks; scheduler) ≈
                  mapreduce(x -> sin.(x), vcat, chnks)
            @test tcollect(chnks; scheduler) == collect(chnks)
            @test treduce(vcat, chnks; scheduler) == reduce(vcat, chnks)
            @test isnothing(tforeach(x -> sin.(x), chnks; scheduler))
        end
    end
end;

@testset "macro API" begin
    # basic
    @test @tasks(for i in 1:3
        i
    end) |> isnothing

    # reduction
    @test @tasks(for i in 1:3
        @set reducer=(+)
        i
    end) == 6

    # scheduler settings
    for sched in (StaticScheduler(), DynamicScheduler(), GreedyScheduler())
        @test @tasks(for i in 1:3
            @set scheduler=sched
            i
        end) |> isnothing
    end
    # scheduler settings as symbols
    @test @tasks(for i in 1:3
        @set scheduler=:static
        i
    end) |> isnothing
    @test @tasks(for i in 1:3
        @set scheduler=:dynamic
        i
    end) |> isnothing
    @test @tasks(for i in 1:3
        @set scheduler=:greedy
        i
    end) |> isnothing

    # @set begin ... end
    @test @tasks(for i in 1:10
        @set begin
            scheduler=StaticScheduler()
            reducer=(+)
        end
        i
    end) == 55
    # multiple @set
    @test @tasks(for i in 1:10
        @set scheduler=StaticScheduler()
        i
        @set reducer=(+)
    end) == 55
    # @set init
    @test @tasks(for i in 1:10
        @set begin
            reducer=(+)
            init=0.0
        end
        i
    end) === 55.0
    @test @tasks(for i in 1:10
        @set begin
            reducer=(+)
            init=0.0*im
        end
        i
    end) === (55.0 + 0.0im)

    # top-level "kwargs"
    @test @tasks(for i in 1:3
        @set scheduler=:static
        @set ntasks=1
        i
    end) |> isnothing
    @test @tasks(for i in 1:3
        @set scheduler=:static
        @set nchunks=2
        i
    end) |> isnothing
    @test @tasks(for i in 1:3
        @set scheduler=:dynamic
        @set chunksize=2
        i
    end) |> isnothing
    @test @tasks(for i in 1:3
        @set scheduler=:dynamic
        @set chunking=false
        i
    end) |> isnothing
    @test_throws ArgumentError @tasks(for i in 1:3
        @set scheduler=DynamicScheduler()
        @set chunking=false
        i
    end)
    @test_throws MethodError @tasks(for i in 1:3
        @set scheduler=:serial
        @set chunking=false
        i
    end)
    @test_throws MethodError @tasks(for i in 1:3
        @set scheduler=:dynamic
        @set asd=123
        i
    end)

    # TaskLocalValue
    ntd = 2*Threads.nthreads()
    ptrs = Vector{Ptr{Nothing}}(undef, ntd)
    tids = Vector{UInt64}(undef, ntd)
    tid() = OhMyThreads.Tools.taskid()
    @test @tasks(for i in 1:ntd
        @local C::Vector{Float64} = rand(3)
        @set scheduler=:static
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
    red = (a,b) -> a+b
    n = 2
    @test @tasks(for d in data
        @set scheduler=sched
        @set reducer=red
        var * d
    end) ≈ var * sum(data)
    @test @tasks(for d in data
        @set scheduler=sched_sym
        @set ntasks=n
        @set reducer=red
        var * d
    end) ≈ var * sum(data)

    struct SingleInt
        x::Int
    end
    @test @tasks(for _ in 1:10
        @local C = SingleInt(var)
        @set reducer=+
        C.x
    end) == 10*var
end;

@testset "WithTaskLocals" begin
    let x = TaskLocalValue{Base.RefValue{Int}}(() -> Ref{Int}(0)), y = TaskLocalValue{Base.RefValue{Int}}(() -> Ref{Int}(0))
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
        @test @fetch( f() ) == (1, 1)
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
    for sched in (DynamicScheduler, StaticScheduler)
        @test sched() isa sched
        @test sched(; chunksize=2) isa sched

        @test OhMyThreads.Schedulers.chunking_mode(sched(; chunksize=2)) == OhMyThreads.Schedulers.FixedSize
        @test OhMyThreads.Schedulers.chunking_mode(sched(; nchunks=2)) == OhMyThreads.Schedulers.FixedCount
        @test OhMyThreads.Schedulers.chunking_mode(sched(; chunking=false)) == OhMyThreads.Schedulers.NoChunking
        @test OhMyThreads.Schedulers.chunking_mode(sched(; nchunks=2, chunksize=4, chunking=false)) == OhMyThreads.Schedulers.NoChunking
        @test OhMyThreads.Schedulers.chunking_mode(sched(; nchunks=-2, chunksize=-4, split=:whatever, chunking=false)) == OhMyThreads.Schedulers.NoChunking
        @test OhMyThreads.Schedulers.chunking_enabled(sched(; chunksize=2)) == true
        @test OhMyThreads.Schedulers.chunking_enabled(sched(; nchunks=2)) == true
        @test OhMyThreads.Schedulers.chunking_enabled(sched(; nchunks=-2, chunksize=-4, chunking=false)) == false
        @test OhMyThreads.Schedulers.chunking_enabled(sched(; nchunks=2, chunksize=4, chunking=false)) == false

        @test_throws ArgumentError sched(; nchunks=2, chunksize=3)
        @test_throws ArgumentError sched(; nchunks=0, chunksize=0)
        @test_throws ArgumentError sched(; nchunks=-2, chunksize=-3)

        let scheduler = sched(; chunksize=2)
            @test tmapreduce(sin, +, 1:10; scheduler) ≈ mapreduce(sin, +, 1:10)
            @test tmap(sin, 1:10; scheduler) ≈ map(sin, 1:10)
            @test isnothing(tforeach(sin, 1:10; scheduler))
            @test treduce(+, 1:10; scheduler) ≈ reduce(+, 1:10)
        end
    end
end;

@testset "top-level kwargs" begin
    res_tmr = mapreduce(sin, +, 1:10000)

    # scheduler not given
    @test tmapreduce(sin, +, 1:10000; ntasks=2) ≈ res_tmr
    @test tmapreduce(sin, +, 1:10000; nchunks=2) ≈ res_tmr
    @test tmapreduce(sin, +, 1:10000; split=:scatter) ≈ res_tmr
    @test tmapreduce(sin, +, 1:10000; chunksize=2) ≈ res_tmr
    @test tmapreduce(sin, +, 1:10000; chunking=false) ≈ res_tmr

    # scheduler isa Scheduler
    @test tmapreduce(sin, +, 1:10000; scheduler=StaticScheduler()) ≈ res_tmr
    @test_throws ArgumentError tmapreduce(sin, +, 1:10000; ntasks=2, scheduler=DynamicScheduler())
    @test_throws ArgumentError tmapreduce(sin, +, 1:10000; chunksize=2, scheduler=DynamicScheduler())
    @test_throws ArgumentError tmapreduce(sin, +, 1:10000; split=:scatter, scheduler=StaticScheduler())
    @test_throws ArgumentError tmapreduce(sin, +, 1:10000; ntasks=3, scheduler=SerialScheduler())

    # scheduler isa Symbol
    for s in (:dynamic, :static, :serial, :greedy)
        @test tmapreduce(sin, +, 1:10000; scheduler=s, init=0.0) ≈ res_tmr
    end
    for s in (:dynamic, :static, :greedy)
        @test tmapreduce(sin, +, 1:10000; ntasks=2, scheduler=s, init=0.0) ≈ res_tmr
    end
    for s in (:dynamic, :static)
        @test tmapreduce(sin, +, 1:10000; chunksize=2, scheduler=s) ≈ res_tmr
        @test tmapreduce(sin, +, 1:10000; chunking=false, scheduler=s) ≈ res_tmr
        @test tmapreduce(sin, +, 1:10000; nchunks=3, scheduler=s) ≈ res_tmr
        @test tmapreduce(sin, +, 1:10000; ntasks=3, scheduler=s) ≈ res_tmr
        @test_throws ArgumentError tmapreduce(sin, +, 1:10000; ntasks=3, nchunks=2, scheduler=s) ≈ res_tmr
    end
end;

@testset "empty collections" begin
    for empty_coll in (11:9, Float64[])
        for f in (sin, x->im*x, identity)
            for op in (+, *, min)
                @test_throws ArgumentError tmapreduce(f, op, empty_coll)
                for init in (0.0, 0, 0.0*im, 0f0)
                    @test tmapreduce(f, op, empty_coll; init) == init
                end
                @test tforeach(f, empty_coll) |> isnothing
            end
        end
    end
end;

# Todo way more testing, and easier tests to deal with
