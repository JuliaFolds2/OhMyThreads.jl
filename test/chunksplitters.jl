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
