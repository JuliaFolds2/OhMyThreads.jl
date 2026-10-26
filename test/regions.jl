# for testing @one_by_one region
mutable struct SingleAccessOnly
    in_use::Bool
    const lck::ReentrantLock
    SingleAccessOnly() = new(false, ReentrantLock())
end
function acquire(f, o::SingleAccessOnly)
    lock(o.lck) do
        o.in_use && throw(ErrorException("Already in use!"))
        o.in_use = true
    end
    try
        f()
    finally
        lock(o.lck) do
            !o.in_use && throw(ErrorException("Conflict!"))
            o.in_use = false
        end
    end
end

@testset "regions" begin
    @testset "@one_by_one" begin
        sao = SingleAccessOnly()

        try
            @tasks for i in 1:10
                @set ntasks = 10
                @one_by_one begin
                    acquire(sao) do
                        sleep(0.01)
                    end
                end
            end
        catch ErrorException
            @test false
        else
            @test true
        end


        # test escaping
        let
            x = Ref(0)
            y = Ref(0)
            @tasks for i in 1:10
                @set ntasks = 10

                y[] += 1 # not safe (race condition)
                @one_by_one begin
                    x[] += 1 # parallel-safe because inside of one_by_one region
                    acquire(sao) do
                        sleep(0.01)
                    end
                end
            end
            @test x[] == 10

        end

        test_f = () -> begin
            x = Ref(0)
            y = Ref(0)
            @tasks for i in 1:10
                @set ntasks = 10

                y[] += 1 # not safe (race condition)
                @one_by_one begin
                    x[] += 1 # parallel-safe because inside of one_by_one region
                    acquire(sao) do
                        sleep(0.01)
                    end
                end
            end
            return x[]
        end
        @test test_f() == 10
    end

    @testset "@only_one" begin
        let
            x = Ref(0)
            y = Ref(0)
            try
                @tasks for i in 1:10
                    @set ntasks = 10

                    y[] += 1 # not safe (race condition)
                    @only_one begin
                        x[] += 1 # parallel-safe because only a single task will execute this
                    end
                end
                @test x[] == 1 # only a single task should have incremented x
            catch ErrorException
                @test false
            end
        end

        let
            x = Ref(0)
            y = Ref(0)
            try
                @tasks for i in 1:10
                    @set ntasks = 2

                    y[] += 1 # not safe (race condition)
                    @only_one begin
                        x[] += 1 # parallel-safe because only a single task will execute this
                    end
                end
                @test x[] == 5 # a single task should have incremented x 5 times
            catch ErrorException
                @test false
            end
        end

        test_f = () -> begin
            x = Ref(0)
            y = Ref(0)
            @tasks for i in 1:10
                @set ntasks = 2

                y[] += 1 # not safe (race condition)
                @only_one begin
                    x[] += 1 # parallel-safe because only a single task will execute this
                end
            end
            return x[]
        end
        @test test_f() == 5
    end

    @testset "@only_one + @one_by_one" begin
        x = Ref(0)
        y = Ref(0)
        try
            @tasks for i in 1:10
                @set ntasks = 10

                @only_one begin
                    x[] += 1 # parallel-safe
                end

                @one_by_one begin
                    y[] += 1 # parallel-safe
                end
            end
            @test x[] == 1 && y[] == 10
        catch ErrorException
            @test false
        end
    end
end;

@testset "verbose special macro usage" begin
    # OhMyThreads.@set
    @test @tasks(for i in 1:3
        OhMyThreads.@set reducer = (+)
        i
    end) == 6
    @test @tasks(for i in 1:3
        OhMyThreads.@set begin
            reducer = (+)
        end
        i
    end) == 6
    # OhMyThreads.@local
    ntd = 2 * Threads.nthreads()
    @test @tasks(for i in 1:ntd
        OhMyThreads.@local x::Ref{Int64} = Ref(0)
        OhMyThreads.@set begin
            reducer = (+)
            scheduler = :static
        end
        x[] += 1
        x[]
    end) == @tasks(for i in 1:ntd
        @local x::Ref{Int64} = Ref(0)
        @set begin
            reducer = (+)
            scheduler = :static
        end
        x[] += 1
        x[]
    end)
    # OhMyThreads.@only_one
    let
        x = Ref(0)
        y = Ref(0)
        try
            @tasks for i in 1:10
                OhMyThreads.@set ntasks = 10

                y[] += 1 # not safe (race condition)
                OhMyThreads.@only_one begin
                    x[] += 1 # parallel-safe because only a single task will execute this
                end
            end
            @test x[] == 1 # only a single task should have incremented x
        catch ErrorException
            @test false
        end
    end
    # OhMyThreads.@one_by_one
    test_f = () -> begin
        sao = SingleAccessOnly()
        x = Ref(0)
        y = Ref(0)
        @tasks for i in 1:10
            OhMyThreads.@set ntasks = 10

            y[] += 1 # not safe (race condition)
            OhMyThreads.@one_by_one begin
                x[] += 1 # parallel-safe because inside of one_by_one region
                acquire(sao) do
                    sleep(0.01)
                end
            end
        end
        return x[]
    end
    @test test_f() == 10
end
