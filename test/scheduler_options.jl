@testset "chunking mode + chunksize option" begin
    @test OhMyThreads.Schedulers.chunking_mode(SerialScheduler()) ==
          OhMyThreads.Schedulers.NoChunking
    for sched in (DynamicScheduler, StaticScheduler, GreedyScheduler)
        @test sched() isa sched
        @test sched(; chunksize = 2) isa sched

        @test OhMyThreads.Schedulers.chunking_mode(sched(; chunksize = 2)) ==
              OhMyThreads.Schedulers.FixedSize
        @test OhMyThreads.Schedulers.chunking_mode(sched(; nchunks = 2)) ==
              OhMyThreads.Schedulers.FixedCount
        @test OhMyThreads.Schedulers.chunking_mode(sched(; chunking = false)) ==
              OhMyThreads.Schedulers.NoChunking
        if sched != GreedyScheduler
            # For (Dynamic|Static)Scheduler `chunking = false` disables all chunking
            # arguments
            @test OhMyThreads.Schedulers.chunking_mode(sched(;
                nchunks = 2, chunksize = 4, chunking = false)) ==
                  OhMyThreads.Schedulers.NoChunking
            @test OhMyThreads.Schedulers.chunking_mode(sched(;
                nchunks = nothing, chunksize = nothing, split = :whatever, chunking = false)) ==
                  OhMyThreads.Schedulers.NoChunking
            @test OhMyThreads.Schedulers.chunking_enabled(sched(;
                nchunks = nothing, chunksize = nothing, chunking = false)) == false
            @test OhMyThreads.Schedulers.chunking_enabled(sched(;
                nchunks = 2, chunksize = 4, chunking = false)) == false
        else
            # For GreedyScheduler `nchunks` or `chunksize` overrides `chunking = false`
            @test OhMyThreads.Schedulers.chunking_mode(sched(;
                nchunks = 2, chunking = false)) ==
                  OhMyThreads.Schedulers.FixedCount
            @test OhMyThreads.Schedulers.chunking_mode(sched(;
                chunksize = 2, chunking = false)) ==
                  OhMyThreads.Schedulers.FixedSize
            @test OhMyThreads.Schedulers.chunking_enabled(sched(;
                nchunks = 2, chunking = false)) == true
            @test OhMyThreads.Schedulers.chunking_enabled(sched(;
                chunksize = 4, chunking = false)) == true
        end
        @test OhMyThreads.Schedulers.chunking_enabled(sched(; chunksize = 2)) == true
        @test OhMyThreads.Schedulers.chunking_enabled(sched(; nchunks = 2)) == true
        @test_throws ArgumentError sched(; nchunks = 2, chunksize = 3)
        @test_throws ArgumentError sched(; nchunks = 2, split = :whatever)

        let scheduler = sched(; chunksize = 2, split = :batch)
            @test tmapreduce(sin, +, 1:10; scheduler, init=0.0) ≈ mapreduce(sin, +, 1:10)
            @test treduce(+, 1:10; scheduler, init=0.0) ≈ reduce(+, 1:10)
            @test tmap(sin, Float64, 1:10; scheduler) ≈ map(sin, 1:10)
            @test isnothing(tforeach(sin, 1:10; scheduler))
        end
    end
end;

@testset "top-level kwargs" begin
    res_tmr = mapreduce(sin, +, 1:10000)

    # scheduler not given
    @test tmapreduce(sin, +, 1:10000; ntasks = 2) ≈ res_tmr
    @test tmapreduce(sin, +, 1:10000; nchunks = 2) ≈ res_tmr
    @test tmapreduce(sin, +, 1:10000; split = RoundRobin()) ≈ res_tmr
    @test tmapreduce(sin, +, 1:10000; chunksize = 2) ≈ res_tmr
    @test tmapreduce(sin, +, 1:10000; chunking = false) ≈ res_tmr
    @test tmapreduce(sin, +, 1:10000; minchunksize=10) ≈ res_tmr
    @test tmapreduce(sin, +, 1:10; minchunksize=10) == mapreduce(sin, +, 1:10)

    # scheduler isa Scheduler
    @test tmapreduce(sin, +, 1:10000; scheduler = StaticScheduler()) ≈ res_tmr
    @test_throws ArgumentError tmapreduce(
        sin, +, 1:10000; ntasks = 2, scheduler = DynamicScheduler())
    @test_throws ArgumentError tmapreduce(
        sin, +, 1:10000; chunksize = 2, scheduler = DynamicScheduler())
    @test_throws ArgumentError tmapreduce(
        sin, +, 1:10000; split = RoundRobin(), scheduler = StaticScheduler())
    @test_throws ArgumentError tmapreduce(
        sin, +, 1:10000; ntasks = 3, scheduler = SerialScheduler())

    # scheduler isa Symbol
    for s in (:dynamic, :static, :serial, :greedy)
        @test tmapreduce(sin, +, 1:10000; scheduler = s, init = 0.0) ≈ res_tmr
    end
    for s in (:dynamic, :static, :greedy)
        @test tmapreduce(sin, +, 1:10000; ntasks = 2, scheduler = s, init = 0.0) ≈ res_tmr
    end
    for s in (:dynamic, :static)
        @test tmapreduce(sin, +, 1:10000; chunksize = 2, scheduler = s) ≈ res_tmr
        @test tmapreduce(sin, +, 1:10000; chunking = false, scheduler = s) ≈ res_tmr
        @test tmapreduce(sin, +, 1:10000; nchunks = 3, scheduler = s) ≈ res_tmr
        @test tmapreduce(sin, +, 1:10000; ntasks = 3, scheduler = s) ≈ res_tmr
        @test_throws ArgumentError tmapreduce(
            sin, +, 1:10000; ntasks = 3, nchunks = 2, scheduler = s)≈res_tmr
    end
    @test_throws ArgumentError tmapreduce(sin, +, 1:10000; scheduler = :whatever)
    @test_throws ArgumentError tmapreduce(
        sin, +, 1:10000; threadpool = :whatever, chunking = false)

    # scheduler isa Val
    for (s, S) in ((:dynamic, DynamicScheduler), (:static, StaticScheduler),
        (:serial, SerialScheduler), (:greedy, GreedyScheduler))
        @test tmapreduce(sin, +, 1:10000; scheduler = Val(s), init = 0.0) ≈ res_tmr
        @test OhMyThreads.Implementation._scheduler_from_userinput(Val(s)) isa S
    end
    @test tmapreduce(sin, +, 1:10000; ntasks = 2, scheduler = Val(:static)) ≈ res_tmr
    @test_throws ArgumentError tmapreduce(sin, +, 1:10000; scheduler = Val(:whatever))
end;
@testset "number of chunks for chunksize" begin
    # 1:11 with chunksize=6 is split into 2 chunks ([1:6, 7:11]) and should parallelize
    @test OhMyThreads.Implementation.has_multiple_chunks(
        DynamicScheduler(; chunksize = 6), 1:11)
    @test !OhMyThreads.Implementation.has_multiple_chunks(
        DynamicScheduler(; chunksize = 6), 1:6)
    @test treduce(+, 1:11; chunksize = 6) == sum(1:11)
    @test treduce(+, 1:6; chunksize = 6) == sum(1:6)
    # tmap: one task per chunk
    taskid() = OhMyThreads.Tools.taskid()
    for scheduler in (DynamicScheduler(; chunksize = 6), StaticScheduler(; chunksize = 6))
        @test length(unique(tmap(_ -> taskid(), 1:11; scheduler))) == 2
        @test length(unique(tmap(_ -> taskid(), 1:100; scheduler))) == 17
        @test tmap(OhMyThreads.WithTaskIndex((c, _) -> c), 1:11; scheduler) ==
              [fill(1, 6); fill(2, 5)]
    end
    @test length(unique(tmap(_ -> taskid(), 1:100; ntasks = 4, minchunksize = 10))) == 4
    @test tmap(sin, 1:100; chunksize = 6) == map(sin, 1:100)
end;

@testset "empty collections" begin
    @static if VERSION < v"1.11.0-"
        err = MethodError
    else
        err = ArgumentError
    end
    for empty_coll in (11:9, Float64[])
        for f in (sin, x -> im * x, identity)
            for op in (+, *, min)
                # mapreduce
                for init in (0.0, 0, 0.0 * im, 0.0f0)
                    @test tmapreduce(f, op, empty_coll; init) == init
                end
                # foreach
                @test tforeach(f, empty_coll) |> isnothing
                # reduce
                if op != min
                    @test treduce(op, empty_coll) == reduce(op, empty_coll)
                else
                    @test_throws err treduce(op, empty_coll)
                end
                # map
                @test tmap(f, empty_coll) == map(f, empty_coll)
                @test tmap(f, empty_coll; ntasks = 4) == map(f, empty_coll)
                @test tmap(f, empty_coll; scheduler = :static, chunksize = 2) ==
                      map(f, empty_coll)
                # collect
                @test tcollect(empty_coll) == collect(empty_coll)
            end
        end
    end
end;

@testset "tmap without chunking" begin
    for sched in (DynamicScheduler, StaticScheduler)
        scheduler = sched(; chunking = false)
        # elements that are not valid indices
        @test tmap(x -> 2x, [10, 20, 30]; scheduler) == [20, 40, 60]
        @test tmap(+, [10, 20, 30], [1.5, 2.5, 3.5]; scheduler) == [11.5, 22.5, 33.5]
        A = rand(3, 4)
        @test tmap(sin, A; scheduler) == map(sin, A)
    end
end;

@testset "tmap with SerialScheduler and kwargs" begin
    @test tmap(sin, 1:10; scheduler = :serial, ntasks = 2) == map(sin, 1:10)
end;
