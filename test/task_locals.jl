@testset "WithTaskLocals" begin
    let x = TaskLocalValue{Base.RefValue{Int}}(() -> Ref{Int}(0)),
        y = TaskLocalValue{Base.RefValue{Int}}(() -> Ref{Int}(0))
        # Equivalent to
        # function f()
        #    x[][] += 1
        #    x[][] += 1
        #    x[], y[]
        # end
        f = WithTaskLocals((x, y)) do (x, y)
            function ()
                x[] += 1
                y[] += 1
                x[], y[]
            end
        end
        # Make sure we can call `f` like a regular function
        @test f() == (1, 1)
        @test f() == (2, 2)
        @test @fetch(f()) == (1, 1)
        # Acceptable use of promise_task_local
        @test @fetch(promise_task_local(f)()) == (1, 1)
        # Acceptable use of promise_task_local
        @test promise_task_local(f)() == (3, 3)
        # Acceptable use of promise_task_local
        @test @fetch(promise_task_local(f)()) == (1, 1)
        # Acceptable use of promise_task_local
        g() = @fetch((promise_task_local(f)(); promise_task_local(f)(); f()))
        @test g() == (3, 3)
        @test g() == (3, 3)

        h = promise_task_local(f)
        # Unacceptable use of `promise_task_local`
        # This is essentially testing that if you use `promise_task_local`, then pass that to another task,
        # you could get data races, since we here have a different thread writing to another thread's value.
        @test @fetch(h()) == (4, 4)
        @test @fetch(h()) == (5, 5)
    end
end;
