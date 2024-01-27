using Test, ThreadsBasics

@testset "Basics" begin
    for (f, op, itr) ∈ [(sin, *, rand(ComplexF64, 100)),
                        (cos, +, (1, 2, 3, 4, 5, 6, 7, 8, 9, 10)),
                        ]

        @test tmapreduce(f, op, itr) ≈ mapreduce(f, op, itr) ≈ treducemap(op, f, itr)
        @test treduce(op, itr) ≈ reduce(op, itr)
        @test tmap(f, ComplexF64, collect(itr)) ≈ map(f, itr)
    end
    # https://github.com/JuliaFolds2/SplittablesBase.jl/issues/1
    @test_broken tmapreduce(last, join, Dict(:a =>"one", :b=>"two", :c=>"three", :d=>"four", :e=>"five"))
end

# Todo way more testing
