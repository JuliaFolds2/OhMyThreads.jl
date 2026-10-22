@testset "show schedulers" begin
    nt = Threads.nthreads(:default)

    @test repr("text/plain", DynamicScheduler()) ==
          """
          DynamicScheduler
          ├ Chunking: fixed count ($nt), split :consecutive
          └ Threadpool: default"""

    @test repr(
        "text/plain", DynamicScheduler(; chunking = false, threadpool = :interactive)) ==
          """
          DynamicScheduler
          ├ Chunking: none
          └ Threadpool: interactive"""

    @test repr("text/plain", StaticScheduler()) ==
          """StaticScheduler
          ├ Chunking: fixed count ($nt), split :consecutive
          └ Threadpool: default"""

    @test repr("text/plain", StaticScheduler(; chunksize = 2, split = :scatter)) ==
          """
          StaticScheduler
          ├ Chunking: fixed size (2), split :roundrobin
          └ Threadpool: default"""

    @test repr("text/plain", GreedyScheduler(; chunking = true)) ==
          """
         GreedyScheduler
         ├ Num. tasks: $nt
         ├ Chunking: fixed count ($(10 * nt)), split :roundrobin
         └ Threadpool: default"""
end
