using Test, OhMyThreads

sets_to_test = [
    (~=isapprox, f=sin∘*, op=+, itrs = (rand(ComplexF64, 10, 10), rand(-10:10, 10, 10)), init=complex(0.0))
    (~=isapprox, f=cos, op=max, itrs = (1:100000,), init=0.0)
    (~=(==), f=round, op=vcat, itrs = (randn(1000),), init=Float64[])
    (~=(==), f=last, op=*, itrs = ([1=>"a", 2=>"b", 3=>"c", 4=>"d", 5=>"e"],), init="")
]


@testset "Basics" begin
    for (; ~, f, op, itrs, init) ∈ sets_to_test
        @testset "f=$f, op=$op, itrs::$(typeof(itrs))" begin
            @testset for sched ∈ (StaticScheduler, DynamicScheduler, GreedyScheduler, DynamicScheduler{false})
                @testset for split ∈ (:batch, :scatter)
                    for nchunks ∈ (1, 2, 6)
                        if sched == GreedyScheduler
                            scheduler = sched(; ntasks=nchunks)
                        elseif sched == DynamicScheduler{false}
                            scheduler = DynamicScheduler(; nchunks=0)
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
    chnks = OhMyThreads.chunks(x; n=Threads.nthreads())
    for scheduler in (DynamicScheduler(; nchunks=0), StaticScheduler(; nchunks=0))
        @testset "$scheduler" begin
            @test tmap(x -> sin.(x), chnks; scheduler) ≈ map(x -> sin.(x), chnks)
            @test tmapreduce(x -> sin.(x), vcat, chnks; scheduler) ≈ mapreduce(x -> sin.(x), vcat, chnks)
            @test tcollect(chnks; scheduler) == collect(chnks)
            @test treduce(vcat, chnks; scheduler) == reduce(vcat, chnks)
            @test isnothing(tforeach(x -> sin.(x), chnks; scheduler))
        end
    end
end

# Todo way more testing, and easier tests to deal with
