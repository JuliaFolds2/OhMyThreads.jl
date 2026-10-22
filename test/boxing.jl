if Threads.nthreads() > 1
    @testset "Boxing detection and error" begin
        let
            f1() = tmap(1:10) do i
                A = i
                sleep(rand()/10)
                A
            end
            f2() = tmap(1:10) do i
                local A = i
                sleep(rand()/10)
                A
            end

            @test f1() == 1:10
            @test f2() == 1:10
        end

        let
            f1() = tmap(1:10) do i
                A = i
                sleep(rand()/10)
                A
            end
            f2() = tmap(1:10) do i
                local A = i
                sleep(rand()/10)
                A
            end

            @test_throws BoxedVariableError f1()
            @test f2() == 1:10

            A = 1 # Cause spooky action-at-a-distance by making A outer-local to the whole let block!
        end

        let
            A = 1
            f1() = tmap(1:10) do i
                A = 1
            end
            @test_throws BoxedVariableError f1() == ones(10) # Throws even though the redefinition is 'harmless'

            @allow_boxed_captures begin
                f2() = tmap(1:10) do i
                    A = 1
                end
                @test f2() == ones(10)
            end

            # Can nest allow and disallow because they're scoped values!
            function f3()
                @disallow_boxed_captures begin
                    tmap(1:10) do i
                    A = 1
                    end
                end
            end
            @allow_boxed_captures begin
                @test_throws BoxedVariableError f3() == ones(10)
            end
        end
        @testset "@localize" begin
            A = 1
            if false
                A = 2
            end
            ## This stops A from being boxed!
            v = @localize A tmap(1:2) do _
                A
            end
            @test v == [1, 1]
        end
    end
end
