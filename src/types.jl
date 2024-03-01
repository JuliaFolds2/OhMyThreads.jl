"""
    struct WithTaskLocalValues{F, TLVs <: Tuple{Vararg{TaskLocalValue}}} <: Function

This callable function-like object is meant to represent a function which closes over some
[`TaskLocalValues`](@ref). This is, if you do

```
TLV{T} = TaskLocalValue{T}
f = WithTaskLocalValues((TLV{Int}(() -> 1), TLV{Int}(() -> 2))) do (x, y)
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
`WithTaskLocalValues` closure in order to turn it into something equivalent to
```
let x=x[], y=y[]
    z -> (x + y)/z
end
```
which doesn't have the overhead of accessing the `tasklocal_storage` each time
the function is called.
"""
struct WithTaskLocalValues{F, TLVs <: Tuple{Vararg{TaskLocalValue}}} <: Function
    inner_func::F
    tasklocalvalues::TLVs
    # function WithTaskLocalValues(f::F, args...) where {F}
    #     new{F, typeof(args)}(f, args)
    # end
end

"""
    promise_task_local(f) = f
    promise_task_local(f::WithTaskLocalValues) = f.inner_func(map(x -> x[], f.tasklocalvalues)...)

Take a `WithTaskLocalValues` closure, grab the `TaskLocalValue`s, and passs them to the closure. That is,
it turns a `WithTaskLocalValues` closure from the equivalent of
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
"""
function promise_task_local(f::WithTaskLocalValues{F}) where {F}
    f.inner_func(map(x -> x[], f.tasklocalvalues))
end
promise_task_local(f::Any) = f

function (f::WithTaskLocalValues{F})(args...; kwargs...) where {F}
    promise_task_local(f)(args...; kwargs...)
end
