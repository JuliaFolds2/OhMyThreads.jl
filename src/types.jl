"""
    struct WithTaskLocals{F, TLVs <: Tuple{Vararg{TaskLocalValue}}} <: Function

This callable function-like object is meant to represent a function which closes over some
[`TaskLocalValues`](https://github.com/vchuravy/TaskLocalValues.jl). This is, if you do

```
TLV{T} = TaskLocalValue{T}
f = WithTaskLocals((TLV{Int}(() -> 1), TLV{Int}(() -> 2))) do (x, y)
    z -> (x + y)/z
end
```
then that is equivalent to
```
g = let x = TLV{Int}(() -> 1), y = TLV{Int}(() -> 2)
    z -> let x = x[], y=y[]
        (x + y)/z
    end
end
```
however, the main difference is that you can call [`promise_task_local`](@ref) on a
`WithTaskLocals` closure in order to turn it into something equivalent to
```
let x=x[], y=y[]
    z -> (x + y)/z
end
```
which doesn't have the overhead of accessing the `task_local_storage` each time the closure is called.
This of course will lose the safety advantages of `TaskLocalValue`, so you should never do
`f_local = promise_task_local(f)` and then pass `f_local` to some unknown function, because if that
unknown function calls `f_local` on a new task, you'll hit a race condition.
"""
struct WithTaskLocals{F, TLVs <: Tuple{Vararg{TaskLocalValue}}} <: Function
    inner_func::F
    tasklocals::TLVs
end

"""
    promise_task_local(f) = f
    promise_task_local(f::WithTaskLocals) = f.inner_func(map(x -> x[], f.tasklocals))

Take a `WithTaskLocals` closure, grab the `TaskLocalValue`s, and passs them to the closure. That is,
it turns a `WithTaskLocals` closure from the equivalent of
```
TLV{T} = TaskLocalValue{T}
let x = TLV{Int}(() -> 1), y = TLV{Int}(() -> 2)
    z -> let x = x[], y=y[]
        (x + y)/z
    end
end
```
into the equivalent of
```
let x = TLV{Int}(() -> 1), y = TLV{Int}(() -> 2)
    let x = x[], y = y[]
        z -> (x + y)/z
    end
end
```
which doesn't have the overhead of accessing the `task_local_storage` each time the closure is called.
This of course will lose the safety advantages of `TaskLocalValue`, so you should never do
`f_local = promise_task_local(f)` and then pass `f_local` to some unknown function, because if that
unknown function calls `f_local` on a new task, you'll hit a race condition. 
```
"""
function promise_task_local(f::WithTaskLocals{F}) where {F}
    f.inner_func(map(x -> x[], f.tasklocals))
end
promise_task_local(f::Any) = f

function (f::WithTaskLocals{F})(args...; kwargs...) where {F}
    promise_task_local(f)(args...; kwargs...)
end

"""
    ChannelLike(itr)

This struct wraps an indexable object such that it can be iterated by concurrent tasks in a
safe manner similar to a `Channel`.

`ChannelLike(itr)` is conceptually similar to:
```julia
Channel{eltype(itr)}(length(itr)) do ch
    foreach(i -> put!(ch, i), itr)
end
```
i.e. creating a channel, `put!`ing all elements of `itr` into it and closing it. The
advantage is that `ChannelLike` doesn't copy the data.

# Examples
```julia
ch = OhMyThreads.ChannelLike(1:5)

@sync for taskid in 1:2
    Threads.@spawn begin
        for i in ch
            println("Task #\$taskid processing item \$i")
            sleep(1 / i)
        end
    end
end

# output

Task #1 processing item 1
Task #2 processing item 2
Task #2 processing item 3
Task #2 processing item 4
Task #1 processing item 5
```

Note that `ChannelLike` is stateful (just like a `Channel`), so you can't iterate over it
twice.

The wrapped iterator must support `firstindex(itr)::Int`, `lastindex(itr)::Int` and
`getindex(itr, ::Int)`.
"""
mutable struct ChannelLike{T}
    const itr::T
    @atomic idx::Int
    function ChannelLike(itr::T) where {T}
        return new{T}(itr, firstindex(itr) - 1)
    end
end

Base.length(ch::ChannelLike) = length(ch.itr)
Base.eltype(ch::ChannelLike) = eltype(ch.itr)

function Base.iterate(ch::ChannelLike, ::Nothing = nothing)
    this = @atomic ch.idx += 1
    if this <= lastindex(ch.itr)
        return (@inbounds(ch.itr[this]), nothing)
    else
        return nothing
    end
end
