@testset "@barrier" begin
    @test (@tasks for i in 1:20
        @set ntasks = 20
        @barrier
    end) |> isnothing

    @test try
        @macroexpand @tasks for i in 1:20
            @barrier
        end
        false
    catch
        true
    end

    @test try
        x = Threads.Atomic{Int64}(0)
        y = Threads.Atomic{Int64}(0)
        @tasks for i in 1:20
            @set ntasks = 20

            Threads.atomic_add!(x, 1)
            @barrier
            if x[] < 20 && y[] > 0 # x hasn't reached 20 yet and y is already > 0
                error("shouldn't happen")
            end
            Threads.atomic_add!(y, 1)
        end
        true
    catch ErrorException
        false
    end

    @test try
        x = Threads.Atomic{Int64}(0)
        y = Threads.Atomic{Int64}(0)
        @tasks for i in 1:20
            @set ntasks = 20

            Threads.atomic_add!(x, 1)
            @barrier
            Threads.atomic_add!(x, 1)
            @barrier
            if x[] < 40 && y[] > 0 # x hasn't reached 20 yet and y is already > 0
                error("shouldn't happen")
            end
            Threads.atomic_add!(y, 1)
        end
        true
    catch ErrorException
        false
    end
end
