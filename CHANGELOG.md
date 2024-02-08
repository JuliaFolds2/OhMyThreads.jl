OhMyThreads.jl Changelog
=========================

Version 0.4.0
-------------

- ![BREAKING][badge-breaking] Instead of taking keyword arguments `schedule`, `nchunks`, `split` directly, we now use `Scheduler` structs to specify scheduling options ([#22](https://github.com/JuliaFolds2/OhMyThreads.jl/issues/22)). The latter can be provided to all API functions via the new `scheduler` keyword argument.
- ![BREAKING][badge-breaking] The default scheduler (`DynamicScheduler`) now, by default, creates `2*nthreads()` tasks to provide load-balancing by default. The old behavior can be restored with `DynamicScheduler(; nchunks=nthreads())`.
- ![Enhancement][badge-enhancement] We reject unsupported keyword arguments early and give a more helpful error message.

Version 0.3.1
-------------

- ![Bugfix][badge-bugfix] The documented Public API wasn't updated in 0.3.0 and thus out of sync with the actual API. Fixed in this version.

Version 0.3.0
-------------

- ![BREAKING][badge-breaking] We don't (re-)export `chunks` anymore. Use `OhMyThreads.chunks` instead.
- ![Feature][badge-feature] We now provide `OhMyThreads.TaskLocalValue` (from [TaskLocalValue.jl](https://github.com/vchuravy/TaskLocalValues.jl)) as a nice solution for task-local values. See the corresponding page in the documentation ([#25][gh-issue-25]).
- ![Enhancement][badge-enhancement] Added a few missing `@views`.
- ![Enhancement][badge-enhancement] Added three examples to the docs: monte carlo, julia set, and trapazoidal integration.
- ![Enhancement][badge-enhancement] Improved all docstrings of the exported API functions. Keyword options are now only shown in the extended help (e.g. `??tmap`) ([#27][gh-issue-27]).
- ![Enhancement][badge-enhancement] Added a translation page that hopefully helps with the Base.Threads → OhMyThreads.jl transition ([#24][gh-issue-24]).

Version 0.2.1
-------------

- ![Enhancement][badge-enhancement] Basic documentation.
- ![Enhancement][badge-enhancement] Making `ChunkSplitters` available internally.

Version 0.2.0
-------------

- Initial version.

[badge-breaking]: https://img.shields.io/badge/BREAKING-red.svg
[badge-deprecation]: https://img.shields.io/badge/Deprecation-orange.svg
[badge-feature]: https://img.shields.io/badge/Feature-green.svg
[badge-enhancement]: https://img.shields.io/badge/Enhancement-blue.svg
[badge-bugfix]: https://img.shields.io/badge/Bugfix-purple.svg
[badge-fix]: https://img.shields.io/badge/Fix-purple.svg
[badge-info]: https://img.shields.io/badge/Info-gray.svg

[gh-issue-27]: https://github.com/JuliaFolds2/OhMyThreads.jl/issues/27
[gh-issue-24]: https://github.com/JuliaFolds2/OhMyThreads.jl/issues/24
[gh-issue-25]: https://github.com/JuliaFolds2/OhMyThreads.jl/issues/25

[gh-pr-5]: https://github.com/JuliaFolds2/OhMyThreads.jl/pull/5
