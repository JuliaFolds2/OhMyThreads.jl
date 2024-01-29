"""
    @tspawnat tid -> task
Mimics `Threads.@spawn`, but assigns the task to thread `tid` (with `sticky = true`).

# Example
```julia
julia> t = @tspawnat 4 Threads.threadid();

julia> fetch(t)
4
```
"""
macro tspawnat(thrdid, expr)
    letargs = Base._lift_one_interp!(expr)

    thunk = esc(:(() -> ($expr)))
    var = esc(Base.sync_varname)
    tid = esc(thrdid)
    @static if VERSION < v"1.9-"
        nt = :(Threads.nthreads())
    else
        nt = :(Threads.maxthreadid())
    end
    quote
        if $tid < 1 || $tid > $nt
            throw(ArgumentError("Invalid thread id ($($tid)). Must be between in " *
                                "1:(total number of threads), i.e. $(1:$nt)."))
        end
        let $(letargs...)
            local task = Task($thunk)
            task.sticky = true
            ccall(:jl_set_task_tid, Cvoid, (Any, Cint), task, $tid - 1)
            if $(Expr(:islocal, var))
                put!($var, task)
            end
            schedule(task)
            task
        end
    end
end

"""
threadids(threadpool = :default) -> Vector{Int}

Returns the thread ids of the threads in the given threadpool.

Supported values for `threadpool` are `:default`, `:interactive`, and `:all`, where the latter
provides all thread ids with default threads coming first.
"""
function threadids(threadpool = :default)::Vector{Int}
    @static if VERSION < v"1.9-"
        return collect(1:nthreads())
    else
        if threadpool == :all
            nt = nthreads(:default) + nthreads(:interactive)
            tids_default = filter(i -> Threads.threadpool(i) == :default, 1:Threads.maxthreadid())
            tids_interactive = filter(i -> Threads.threadpool(i) == :interactive, 1:Threads.maxthreadid())
            tids = vcat(tids_default, tids_interactive)
        else
            nt = nthreads(threadpool)
            tids = filter(i -> Threads.threadpool(i) == threadpool, 1:Threads.maxthreadid())
        end

        if nt != length(tids)
            # IJulia manually adds a heartbeat thread that mus be ignored...
            # see https://github.com/JuliaLang/IJulia.jl/issues/1072
            # Currently, we just assume that it is the last thread.
            # Might not be safe, in particular not once users can dynamically add threads
            # in the future.
            pop!(tids)
        end
        return tids
    end
end
