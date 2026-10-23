module ProgressMeterExt

using OhMyThreads: tmap, tmap!, tforeach, tmapreduce, treducemap, treduce, WithTaskIndex
using ProgressMeter: ProgressMeter, Progress, ncalls, ncalls_map, ncalls_reduce

ProgressMeter.ncalls(::typeof(tmap), ::Function, args...) = ncalls_map(args...)
ProgressMeter.ncalls(::typeof(tmap), ::Function, ::Type, args...) = ncalls_map(args...)
ProgressMeter.ncalls(::typeof(tmap!), ::Function, args...) = ncalls_map(args...)
ProgressMeter.ncalls(::typeof(tforeach), ::Function, args...) = ncalls_map(args...)
ProgressMeter.ncalls(::typeof(tmapreduce), ::Function, ::Function, args...) = ncalls_map(args...)
ProgressMeter.ncalls(::typeof(treducemap), ::Function, ::Function, args...) = ncalls_map(args...)
ProgressMeter.ncalls(::typeof(treduce), ::Function, arg) = ncalls_reduce(arg)

# `progress_map` wraps the mapped function in a closure which would hide the `WithTaskIndex`
# from OhMyThreads. Therefore, we unwrap it here and re-wrap the closure instead.
function ProgressMeter.progress_map(f::WithTaskIndex, args...; mapfun = map,
        progress = Progress(ncalls(mapfun, f, args...)),
        channel_bufflen = min(1000, ncalls(mapfun, f, args...)),
        kwargs...)
    mapfun_rewrap = (g, xs...; kw...) -> mapfun(WithTaskIndex(g), xs...; kw...)
    return ProgressMeter.progress_map(f.f, args...; mapfun = mapfun_rewrap, progress,
        channel_bufflen, kwargs...)
end

end
