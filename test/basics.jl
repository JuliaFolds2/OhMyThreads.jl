sets_to_test = [(~ = isapprox, f = sin ∘ *, op = +,
                    itrs = (rand(ComplexF64, 10, 10), rand(-10:10, 10, 10)),
                    init = complex(0.0))
                (~ = isapprox, f = cos, op = max, itrs = (1:100000,), init = 0.0)
                (~ = (==), f = round, op = vcat, itrs = (randn(1000),), init = Float64[])
                (~ = (==), f = last, op = *,
                    itrs = ([1 => "a", 2 => "b", 3 => "c", 4 => "d", 5 => "e"],),
                    init = "")]

@testset "Basics" begin
    for (; ~, f, op, itrs, init) in sets_to_test
        @testset "f=$f, op=$op, itrs::$(typeof(itrs))" begin
            @testset for sched in (
                StaticScheduler, DynamicScheduler, GreedyScheduler,
                DynamicScheduler{OhMyThreads.Schedulers.NoChunking},
                SerialScheduler, ChunkedGreedy)
                @testset for split in (Consecutive(), RoundRobin(), :consecutive, :roundrobin)
                    for nchunks in (1, 2, 6)
                        for minchunksize ∈ (nothing, 1, 3)
                            if sched == GreedyScheduler
                                scheduler = sched(; ntasks = nchunks, minchunksize)
                            elseif sched == DynamicScheduler{OhMyThreads.Schedulers.NoChunking}
                                scheduler = DynamicScheduler(; chunking = false)
                            elseif sched == SerialScheduler
                                scheduler = SerialScheduler(; nchunks)
                            else
                                scheduler = sched(; nchunks, split, minchunksize)
                            end
                            kwargs = (; scheduler)
                            if (split in (RoundRobin(), :roundrobin) ||
                                sched ∈ (GreedyScheduler, ChunkedGreedy)) || op ∉ (vcat, *)
                                # scatter and greedy only works for commutative operators!
                            else
                                mapreduce_f_op_itr = mapreduce(f, op, itrs...)
                                @test tmapreduce(f, op, itrs...; init, kwargs...) ~ mapreduce_f_op_itr
                                @test treducemap(op, f, itrs...; init, kwargs...) ~ mapreduce_f_op_itr
                                @test treduce(op, f.(itrs...); init, kwargs...) ~ mapreduce_f_op_itr
                            end

                            split in (RoundRobin(), :roundrobin) && continue
                            map_f_itr = map(f, itrs...)
                            @test all(tmap(f, Any, itrs...; kwargs...) .~ map_f_itr)
                            @test all(tcollect(Any, (f(x...) for x in collect(zip(itrs...))); kwargs...) .~ map_f_itr)
                            @test all(tcollect(Any, f.(itrs...); kwargs...) .~ map_f_itr)

                            RT = Core.Compiler.return_type(f, Tuple{eltype.(itrs)...})

                            @test tmap(f, RT, itrs...; kwargs...) ~ map_f_itr
                            @test tcollect(RT, (f(x...) for x in collect(zip(itrs...))); kwargs...) ~ map_f_itr
                            @test tcollect(RT, f.(itrs...); kwargs...) ~ map_f_itr

                            if sched ∉ (GreedyScheduler, ChunkedGreedy)
                                @test tmap(f, itrs...; kwargs...) ~ map_f_itr
                                @test tcollect((f(x...) for x in collect(zip(itrs...))); kwargs...) ~ map_f_itr
                                @test tcollect(f.(itrs...); kwargs...) ~ map_f_itr
                            end
                        end
                    end
                end
            end
        end
    end
end;
