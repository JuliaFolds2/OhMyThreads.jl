module ProgressMeterExt

using OhMyThreads: tmap, tmap!, tforeach, tmapreduce, treducemap, treduce
using ProgressMeter: ProgressMeter, ncalls_map, ncalls_reduce

ProgressMeter.ncalls(::typeof(tmap), ::Function, args...) = ncalls_map(args...)
ProgressMeter.ncalls(::typeof(tmap), ::Function, ::Type, args...) = ncalls_map(args...)
ProgressMeter.ncalls(::typeof(tmap!), ::Function, args...) = ncalls_map(args...)
ProgressMeter.ncalls(::typeof(tforeach), ::Function, args...) = ncalls_map(args...)
ProgressMeter.ncalls(::typeof(tmapreduce), ::Function, ::Function, args...) = ncalls_map(args...)
ProgressMeter.ncalls(::typeof(treducemap), ::Function, ::Function, args...) = ncalls_map(args...)
ProgressMeter.ncalls(::typeof(treduce), ::Function, arg) = ncalls_reduce(arg)

end
