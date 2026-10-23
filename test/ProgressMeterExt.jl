using Test, OhMyThreads, ProgressMeter

@testset "ProgressMeterExt" begin
    data = rand(1000)

    @testset "tmap" begin
        map_result = map(sin, data)
        @testset for scheduler in (:dynamic, :static, :serial)
            @test (@showprogress desc="tmap ($scheduler)" tmap(sin, data; scheduler)) ≈ map_result
        end
        # greedy requires explicit output type
        @test (@showprogress desc="tmap (greedy)" tmap(sin, Float64, data; scheduler = :greedy)) ≈ map_result
    end

    @testset "tmap!" begin
        @testset for scheduler in (:dynamic, :static, :greedy, :serial)
            out = similar(data)
            @showprogress desc="tmap! ($scheduler)" tmap!(sin, out, data; scheduler)
            @test out ≈ map(sin, data)
        end
    end

    @testset "tforeach" begin
        @testset for scheduler in (:dynamic, :static, :greedy, :serial)
            @test (@showprogress desc="tforeach ($scheduler)" tforeach(sin, data; scheduler)) |> isnothing
        end
    end

    @testset "tmapreduce" begin
        mapreduce_result = mapreduce(sin, +, data)
        @testset for scheduler in (:dynamic, :static, :greedy, :serial)
            @test (@showprogress desc="tmapreduce ($scheduler)" tmapreduce(sin, +, data; scheduler)) ≈ mapreduce_result
        end
    end

    @testset "treducemap" begin
        mapreduce_result = mapreduce(sin, +, data)
        @testset for scheduler in (:dynamic, :static, :greedy, :serial)
            @test (@showprogress desc="treducemap ($scheduler)" treducemap(+, sin, data; scheduler)) ≈ mapreduce_result
        end
    end

    @testset "treduce" begin
        reduce_result = reduce(+, data)
        @testset for scheduler in (:dynamic, :static, :greedy, :serial)
            @test (@showprogress desc="treduce ($scheduler)" treduce(+, data; scheduler)) ≈ reduce_result
        end
    end

    @testset "WithTaskIndex" begin
        f = OhMyThreads.WithTaskIndex((idx, x) -> (idx, sin(x)))
        expected = collect(zip(repeat(1:4; inner = 25), map(sin, data[1:100])))
        @test (@showprogress desc="tmap (WithTaskIndex)" tmap(f, data[1:100]; ntasks = 4)) == expected
        out = similar(expected)
        @showprogress desc="tmap! (WithTaskIndex)" tmap!(f, out, data[1:100]; ntasks = 4)
        @test out == expected
        @test (@showprogress desc="tmapreduce (WithTaskIndex)" tmapreduce(f, vcat, data[1:100]; ntasks = 4)) == expected
        idxs = zeros(Int, 100)
        g = OhMyThreads.WithTaskIndex((idx, i) -> idxs[i] = idx)
        @showprogress desc="tforeach (WithTaskIndex)" tforeach(g, 1:100; ntasks = 4)
        @test idxs == repeat(1:4; inner = 25)
    end
end
