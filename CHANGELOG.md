OhMyThreads.jl Changelog
=========================

Version 0.5.0
-------------

- ![Feature][badge-feature] The `DynamicScheduler` (default) now supports a `chunksize` argument to specify the desired size of chunks instead of the number of chunks (`nchunks`). Note that `chunksize` and `nchunks` are mutually exclusive.
- ![Feature][badge-feature] `@set init = ...` may now be used to specify an initial value for a reduction (only has an effect in conjuction with `@set reducer=...` and triggers a warning otherwise).
- ![BREAKING][badge-breaking] Within a `@tasks` block, task-local values must from now on be defined via `@local` instead of `@init` (renamed).
- ![BREAKING][badge-breaking] The (already deprecated) `SpawnAllScheduler` has been dropped.

Version 0.4.6
-------------

- ![Feature][badge-feature] Introduction of macro API (`@tasks`) that transforms for loops into corresponding `tforeach`, `tmapreduce`, and `tmap` calls. This new API enables us to facilitate certain patterns, like defining task local values.

Version 0.4.5
-------------

- ![Enhancement][badge-enhancement] Improved the thread-safe storage section of the documentation.

Version 0.4.4
-------------

- ![Bugfix][badge-bugfix] Fixed a type specification bug that could occur when passing a `Chunk` into, say, `tmapreduce`.

Version 0.4.3
-------------

- ![Feature][badge-feature] Forward (but don't export) the macros `@fetch` and `@fetchfrom` from StableTasks.jl (v0.1.5), which are analogous to the same-named macros in Distributed.jl.

Version 0.4.2
-------------

- ![Feature][badge-feature] `DynamicScheduler` now supports `nchunks=0`, which turns off internal chunking entirely.
- ![Deprecation][badge-deprecation] `SpawnAllScheduler` is now deprecated in favor of `DynamicScheduler(; nchunks=0)`.
- ![Feature][badge-feature] Partial support for passing in a `ChunkSplitters.Chunk` when using `DynamicScheduler` (default). In this case, one should generally use `DynamicScheduler(; nchunks=0)`, i.e. turn off internal chunking.
- ![Feature][badge-feature] `StaticScheduler` now supports `nchunks=0`, which turns off internal chunking entirely. Only works for input that has `<= nthreads()` elements.

Version 0.4.1
-------------

- ![Feature][badge-feature] Added a new, simple `SpawnAllScheduler` that spawns a task per input element (can be a lot of tasks!).
- ![Info][badge-info] Added downgrade_CI which makes sure the testsuite works on the oldest versions of dependancies.

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
