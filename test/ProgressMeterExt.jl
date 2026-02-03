using Test, OhMyThreads, ProgressMeter

@testset "ProgressMeterExt" begin
    data = rand(1000)

    @testset "tmap" begin
        map_result = map(sin, data)
        @testset for scheduler in (:dynamic, :static, :serial)
            @test (@showprogress dt=0 desc="tmap ($scheduler)" tmap(sin, data; scheduler)) ≈ map_result
        end
        # greedy requires explicit output type
        @test (@showprogress dt=0 desc="tmap (greedy)" tmap(sin, Float64, data; scheduler = :greedy)) ≈ map_result
    end

    @testset "tmap!" begin
        @testset for scheduler in (:dynamic, :static, :greedy, :serial)
            out = similar(data)
            @showprogress dt=0 desc="tmap! ($scheduler)" tmap!(sin, out, data; scheduler)
            @test out ≈ map(sin, data)
        end
    end

    @testset "tforeach" begin
        @testset for scheduler in (:dynamic, :static, :greedy, :serial)
            @test (@showprogress dt=0 desc="tforeach ($scheduler)" tforeach(sin, data; scheduler)) |> isnothing
        end
    end

    @testset "tmapreduce" begin
        mapreduce_result = mapreduce(sin, +, data)
        @testset for scheduler in (:dynamic, :static, :greedy, :serial)
            @test (@showprogress dt=0 desc="tmapreduce ($scheduler)" tmapreduce(sin, +, data; scheduler)) ≈ mapreduce_result
        end
    end

    @testset "treducemap" begin
        mapreduce_result = mapreduce(sin, +, data)
        @testset for scheduler in (:dynamic, :static, :greedy, :serial)
            @test (@showprogress dt=0 desc="treducemap ($scheduler)" treducemap(+, sin, data; scheduler)) ≈ mapreduce_result
        end
    end

    @testset "treduce" begin
        reduce_result = reduce(+, data)
        @testset for scheduler in (:dynamic, :static, :greedy, :serial)
            @test (@showprogress dt=0 desc="treduce ($scheduler)" treduce(+, data; scheduler)) ≈ reduce_result
        end
    end
end
