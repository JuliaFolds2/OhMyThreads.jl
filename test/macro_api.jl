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
