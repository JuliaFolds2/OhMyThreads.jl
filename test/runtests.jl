using Test, OhMyThreads

sets_to_test = [(~ = isapprox, f = sin ∘ *, op = +,
                    itrs = (rand(ComplexF64, 10, 10), rand(-10:10, 10, 10)),
                    init = complex(0.0))
                (~ = isapprox, f = cos, op = max, itrs = (1:100000,), init = 0.0)
                (~ = (==), f = round, op = vcat, itrs = (randn(1000),), init = Float64[])
                (~ = (==), f = last, op = *,
                    itrs = ([1 => "a", 2 => "b", 3 => "c", 4 => "d", 5 => "e"],),
                    init = "")]

@testset "Basics" begin
    for (; ~, f, op, itrs, init) in sets_to_test
        @testset "f=$f, op=$op, itrs::$(typeof(itrs))" begin
            @testset for sched in (
                StaticScheduler, DynamicScheduler, GreedyScheduler, DynamicScheduler{OhMyThreads.Schedulers.NoChunking})
                @testset for split in (:batch, :scatter)
                    for nchunks in (1, 2, 6)
                        if sched == GreedyScheduler
                            scheduler = sched(; ntasks = nchunks)
                        elseif sched == DynamicScheduler{OhMyThreads.Schedulers.NoChunking}
                            scheduler = DynamicScheduler(; nchunks = 0)
                        else
                            scheduler = sched(; nchunks, split)
                        end

                        kwargs = (; scheduler)
                        if (split == :scatter || sched == GreedyScheduler) || op ∉ (vcat, *)
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

                        if sched !== GreedyScheduler
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

@testset "ChunkSplitters.Chunk" begin
    x = rand(100)
    chnks = OhMyThreads.chunks(x; n = Threads.nthreads())
    for scheduler in (DynamicScheduler(; nchunks = 0), StaticScheduler(; nchunks = 0))
        @testset "$scheduler" begin
            @test tmap(x -> sin.(x), chnks; scheduler) ≈ map(x -> sin.(x), chnks)
            @test tmapreduce(x -> sin.(x), vcat, chnks; scheduler) ≈
                  mapreduce(x -> sin.(x), vcat, chnks)
            @test tcollect(chnks; scheduler) == collect(chnks)
            @test treduce(vcat, chnks; scheduler) == reduce(vcat, chnks)
            @test isnothing(tforeach(x -> sin.(x), chnks; scheduler))
        end
    end
end

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
    end) == 55.0
    @test @tasks(for i in 1:10
        @set begin
            reducer=(+)
            init=0.0*im
        end
        i
    end) == (55.0 + 0.0im)


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
    # TaskLocalValue (begin ... end block)
    @test @tasks(for i in 1:10
        @local begin
            C::Matrix{Int64} = fill(4, 3, 3)
            x::Vector{Float64} = fill(5.0, 3)
        end
        @set reducer = (+)
        sum(C * x)
    end) == 1800

    # hygiene / escaping
    var = 3
    sched = StaticScheduler()
    data = rand(10)
    red = (a,b) -> a+b
    @test @tasks(for d in data
        @set scheduler=sched
        @set reducer=red
        var * d
    end) ≈ var * sum(data)

    struct SingleInt
        x::Int
    end
    @test @tasks(for _ in 1:10
        @local C::SingleInt = SingleInt(var)
        @set reducer=+
        C.x
    end) == 10*var
end

@testset "chunking mode + chunksize option" begin
    @test DynamicScheduler(; chunksize=2) isa DynamicScheduler
    @test StaticScheduler(; chunksize=2) isa StaticScheduler

    @test OhMyThreads.Schedulers.chunking_mode(DynamicScheduler(; chunksize=2)) == OhMyThreads.Schedulers.FixedSize
    @test OhMyThreads.Schedulers.chunking_mode(DynamicScheduler(; nchunks=2)) == OhMyThreads.Schedulers.FixedCount
    @test OhMyThreads.Schedulers.chunking_mode(DynamicScheduler(; nchunks=0, chunksize=0)) == OhMyThreads.Schedulers.NoChunking
    @test OhMyThreads.Schedulers.chunking_mode(DynamicScheduler(; nchunks=0)) == OhMyThreads.Schedulers.NoChunking
    @test OhMyThreads.Schedulers.chunking_enabled(DynamicScheduler(; chunksize=2)) == true
    @test OhMyThreads.Schedulers.chunking_enabled(DynamicScheduler(; nchunks=2)) == true
    @test OhMyThreads.Schedulers.chunking_enabled(DynamicScheduler(; nchunks=0, chunksize=0)) == false
    @test OhMyThreads.Schedulers.chunking_enabled(DynamicScheduler(; nchunks=0)) == false

    @test OhMyThreads.Schedulers.chunking_mode(StaticScheduler(; chunksize=2)) == OhMyThreads.Schedulers.FixedSize
    @test OhMyThreads.Schedulers.chunking_mode(StaticScheduler(; nchunks=2)) == OhMyThreads.Schedulers.FixedCount
    @test OhMyThreads.Schedulers.chunking_mode(StaticScheduler(; nchunks=0, chunksize=0)) == OhMyThreads.Schedulers.NoChunking
    @test OhMyThreads.Schedulers.chunking_mode(StaticScheduler(; nchunks=0)) == OhMyThreads.Schedulers.NoChunking
    @test OhMyThreads.Schedulers.chunking_enabled(StaticScheduler(; chunksize=2)) == true
    @test OhMyThreads.Schedulers.chunking_enabled(StaticScheduler(; nchunks=2)) == true
    @test OhMyThreads.Schedulers.chunking_enabled(StaticScheduler(; nchunks=0, chunksize=0)) == false
    @test OhMyThreads.Schedulers.chunking_enabled(StaticScheduler(; nchunks=0)) == false

    @test_throws ArgumentError DynamicScheduler(; nchunks=2, chunksize=3)
    @test_throws ArgumentError StaticScheduler(; nchunks=2, chunksize=3)

    let scheduler = DynamicScheduler(; chunksize=2)
        @test tmapreduce(sin, +, 1:10; scheduler) ≈ mapreduce(sin, +, 1:10)
        @test tmap(sin, 1:10; scheduler) ≈ map(sin, 1:10)
        @test isnothing(tforeach(sin, 1:10; scheduler))
        @test treduce(+, 1:10; scheduler) ≈ reduce(+, 1:10)
    end
    let scheduler = StaticScheduler(; chunksize=2)
        @test tmapreduce(sin, +, 1:10; scheduler) ≈ mapreduce(sin, +, 1:10)
        @test tmap(sin, 1:10; scheduler) ≈ map(sin, 1:10)
        @test isnothing(tforeach(sin, 1:10; scheduler))
        @test treduce(+, 1:10; scheduler) ≈ reduce(+, 1:10)
    end
end

# Todo way more testing, and easier tests to deal with
