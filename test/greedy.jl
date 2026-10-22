@testset "SizeUnknown iterators (greedy)" begin
    itr = Iterators.filter(isodd, 1:10)
    @test tmapreduce(identity, +, itr; scheduler = :greedy, init = 0) == 25
    @test tmapreduce(x -> x^2, +, itr; scheduler = :greedy, init = 0) ==
          mapreduce(x -> x^2, +, itr)
    @test tforeach(identity, itr; scheduler = :greedy) |> isnothing
    # chunking requires a known size
    @test_throws ArgumentError tmapreduce(
        identity, +, itr; scheduler = GreedyScheduler(; chunking = true), init = 0)
    # other schedulers
    for scheduler in (:dynamic, :static, DynamicScheduler(; chunking = false),
        StaticScheduler(; chunking = false))
        @test_throws "only supported by the `GreedyScheduler`" tmapreduce(
            identity, +, itr; scheduler)
        @test_throws "only supported by the `GreedyScheduler`" tforeach(
            identity, itr; scheduler)
    end
    @test tmapreduce(identity, +, itr; scheduler = :serial) == 25
    # multiple inputs
    for args in ((itr, [1, 2, 3]), ([1, 2, 3], itr))
        @test_throws "can't be combined with other inputs" tmapreduce(
            +, +, args...; scheduler = :greedy)
    end
    # type stability
    @test @inferred(tmapreduce(identity, +, itr; scheduler = GreedyScheduler(), init = 0)) == 25
end;

# An iterator of unknown size that records the task iterating it
mutable struct TaskRecordingIterator
    task::Union{Nothing, Task}
end
Base.IteratorSize(::Type{TaskRecordingIterator}) = Base.SizeUnknown()
Base.eltype(::Type{TaskRecordingIterator}) = Int
function Base.iterate(it::TaskRecordingIterator, i = 1)
    it.task = current_task()
    return i <= 1000 ? (i, i + 1) : nothing
end

@testset "GreedyScheduler: producer terminates if all consumers fail" begin
    it = TaskRecordingIterator(nothing)
    @test_throws TaskFailedException tforeach(x -> error("boom"), it; scheduler = :greedy)
    t0 = time()
    while !istaskdone(it.task) && time() - t0 < 10
        sleep(0.01)
    end
    @test istaskdone(it.task)
end;

# Models an array with a mutable read cache or a shared seek/read handle.
struct SerialReadVector <: AbstractVector{Int}
    reading::Threads.Atomic{Bool}
end
Base.size(::SerialReadVector) = (20,)
Base.IndexStyle(::Type{SerialReadVector}) = IndexLinear()
function Base.getindex(A::SerialReadVector, i::Int)
    Threads.atomic_cas!(A.reading, false, true) && error("concurrent getindex")
    try
        # Allow another worker to attempt a read, including with only one thread.
        sleep(0.001)
        return i
    finally
        Threads.atomic_xchg!(A.reading, false)
    end
end

@testset "GreedyScheduler: custom arrays are read by a single producer" begin
    A = SerialReadVector(Threads.Atomic{Bool}(false))
    scheduler = GreedyScheduler(; ntasks = 4)
    @test @inferred(treduce(+, A; scheduler)) == sum(1:20)
    @test treduce(+, view(A, :); scheduler) == sum(1:20)
    # Every input must support concurrent reads to use the fast path.
    @test tmapreduce(+, +, A, 1:20; scheduler) == 2sum(1:20)
    @test tmapreduce(+, +, 1:20, A; scheduler) == 2sum(1:20)
end;

@testset "GreedyScheduler: type stability" begin
    for scheduler in (GreedyScheduler(), GreedyScheduler(; chunking = true))
        @test @inferred(tmapreduce(sin, +, 1:100; scheduler)) ≈ mapreduce(sin, +, 1:100)
        @test @inferred(treduce(+, 1:100; scheduler)) == sum(1:100)
    end
end;
