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
