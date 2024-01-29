using Test, ThreadsBasics

@testset "Basics" begin
    for (~, f, op, itr) ∈ [
        (isapprox, sin, +, rand(ComplexF64, 10, 10)),
        (isapprox, cos, max, 1:100000),
        (==, round, vcat, randn(1000)),
        (==, last, *, [1=>"a", 2=>"b", 3=>"c", 4=>"d", 5=>"e"])
    ]
        @testset for schedule ∈ (:static, :dynamic,)
            @testset for split ∈ (:batch, :scatter)
                if split == :scatter # scatter only works for commutative operators
                    if op ∈ (vcat, *)
                        continue
                    end
                end
                for nchunks ∈ (1, 2, 6, 10, 100)
                    if schedule == :staitc && nchunks > Threads.nthreads()
                        continue
                    end
                    kwargs = (; schedule, split, nchunks)
                    mapreduce_f_op_itr = mapreduce(f, op, itr)
                    @test tmapreduce(f, op, itr; kwargs...) ~ mapreduce_f_op_itr
                    @test treducemap(op, f, itr; kwargs...) ~ mapreduce_f_op_itr
                    @test treduce(op, f.(itr); kwargs...) ~ mapreduce_f_op_itr

                    map_f_itr = map(f, itr)
                    @test all(tmap(f, Any, itr; kwargs...) .~ map_f_itr)
                    @test all(tcollect(Any, (f(x) for x in itr); kwargs...) .~ map_f_itr)
                    @test all(tcollect(Any, f.(itr); kwargs...) .~ map_f_itr)

                    @test tmap(f, itr; kwargs...) ~ map_f_itr
                    @test tcollect((f(x) for x in itr); kwargs...) ~ map_f_itr
                    @test tcollect(f.(itr); kwargs...) ~ map_f_itr
                    
                    RT = Core.Compiler.return_type(f, Tuple{eltype(itr)})
                    
                    @test tmap(f, RT, itr; kwargs...) ~ map_f_itr
                    @test tcollect(RT, (f(x) for x in itr); kwargs...) ~ map_f_itr
                    @test tcollect(RT, f.(itr); kwargs...) ~ map_f_itr
                end
            end
        end
    end
end

# Todo way more testing, and easier tests to deal with
