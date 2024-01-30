using Test, OhMyThreads

@testset "Basics" begin
    for (~, f, op, itrs) ∈ [
        (isapprox, sin∘*, +, (rand(ComplexF64, 10, 10), rand(-10:10, 10, 10))),
        (isapprox, cos, max, (1:100000,)),
        (==, round, vcat, (randn(1000),)),
        (==, last, *, ([1=>"a", 2=>"b", 3=>"c", 4=>"d", 5=>"e"],))
    ]
        @testset for schedule ∈ (:static, :dynamic, :interactive)
            @testset for split ∈ (:batch, :scatter)
                if split == :scatter # scatter only works for commutative operators
                    if op ∈ (vcat, *)
                        continue
                    end
                end
                for nchunks ∈ (1, 2, 6, 10)
                    if schedule == :static && nchunks > Threads.nthreads()
                        continue
                    end
                    kwargs = (; schedule, split, nchunks)
                    mapreduce_f_op_itr = mapreduce(f, op, itrs...)
                    @test tmapreduce(f, op, itrs...; kwargs...) ~ mapreduce_f_op_itr
                    @test treducemap(op, f, itrs...; kwargs...) ~ mapreduce_f_op_itr
                    @test treduce(op, f.(itrs...); kwargs...) ~ mapreduce_f_op_itr

                    map_f_itr = map(f, itrs...)
                    @test all(tmap(f, Any, itrs...; kwargs...) .~ map_f_itr)
                    @test all(tcollect(Any, (f(x...) for x in collect(zip(itrs...))); kwargs...) .~ map_f_itr)
                    @test all(tcollect(Any, f.(itrs...); kwargs...) .~ map_f_itr)

                    @test tmap(f, itrs...; kwargs...) ~ map_f_itr
                    @test tcollect((f(x...) for x in collect(zip(itrs...))); kwargs...) ~ map_f_itr
                    @test tcollect(f.(itrs...); kwargs...) ~ map_f_itr
                    
                    RT = Core.Compiler.return_type(f, Tuple{eltype.(itrs)...})
                    
                    @test tmap(f, RT, itrs...; kwargs...) ~ map_f_itr
                    @test tcollect(RT, (f(x...) for x in collect(zip(itrs...))); kwargs...) ~ map_f_itr
                    @test tcollect(RT, f.(itrs...); kwargs...) ~ map_f_itr
                end
            end
        end
    end
end

# Todo way more testing, and easier tests to deal with
