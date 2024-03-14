OhMyThreads.jl Changelog
=========================

Version 0.5.0
-------------

- ![Feature][badge-feature] The parallel functions (e.g. tmapreduce etc.) now support `scheduler::Symbol` besides `scheduler::Scheduler`. To configure the selected scheduler (e.g. set `nchunks` etc.) one may now pass keyword arguments directly into the parallel functions (they will get passed on to the scheduler constructor). Example: `tmapreduce(sin, +, 1:10; chunksize=2, scheduler=:static)`. Analogous support has been added to the macro API: (Most) settings (`@set name = value`) will now be passed on to the parallel functions as keyword arguments (which then forward them to the scheduler constructor). Note that, to avoid ambiguity, we don't support this feature for `scheduler::Scheduler` but only for `scheduler::Symbol`.
- ![Feature][badge-feature] Added a `SerialScheduler` that can be used to turn off any multithreading.
- ![Feature][badge-feature] Added `OhMyThreads.WithTaskLocals` that represents a closure over `TaskLocalValues`, but can have those values materialized as an optimization (using `OhMyThreads.promise_task_local`)
- ![Feature][badge-feature] In the case `nchunks > nthreads()`, the `StaticScheduler` now distributes chunks in a round-robin fashion (instead of either implicitly decreasing `nchunks` to `nthreads()` or throwing an error).
- ![Feature][badge-feature] `@set init = ...` may now be used to specify an initial value for a reduction (only has an effect in conjuction with `@set reducer=...` and triggers a warning otherwise).
- ![Enhancement][badge-enhancement] `SerialScheduler` and `DynamicScheduler` now support the keyword argument `ntasks` as an alias for `nchunks`.
- ![Enhancement][badge-enhancement] Made `@tasks` use `OhMyThreads.WithTaskLocals` automatically as an optimization.
- ![Enhancement][badge-enhancement] Uses of `@local` within `@tasks` no-longer require users to declare the type of the task local value, it can be inferred automatically if a type is not provided.
- ![BREAKING][badge-breaking] The `DynamicScheduler` (default) and the `StaticScheduler` now support a `chunksize` argument to specify the desired size of chunks instead of the number of chunks (`nchunks`). Note that `chunksize` and `nchunks` are mutually exclusive. (This is unlikely to break existing code but technically could because the type parameter has changed from `Bool` to `ChunkingMode`.)
- ![Breaking][badge-breaking] `DynamicScheduler` and `StaticScheduler` don't support `nchunks=0` or `chunksize=0` any longer. Instead, chunking can now be turned off via an explicit new keyword argument `chunking=false`.
- ![BREAKING][badge-breaking] Within a `@tasks` block, task-local values must from now on be defined via `@local` instead of `@init` (renamed).
- ![BREAKING][badge-breaking] The (already deprecated) `SpawnAllScheduler` has been dropped.
- ![BREAKING][badge-breaking] The default value for `ntasks`/`nchunks` for `DynamicScheduler` has been changed from `2*nthreads()` to `nthreads()`. With the new value we now align with `@threads :dynamic`. The old value wasn't giving good load balancing anyways and choosing a higher value penalizes uniform use cases even more. To get the old behavior, set `nchunks=2*nthreads()`.
- ![Bugfix][badge-bugfix] When using the `GreedyScheduler` in combination with `tmapreduce` (or functions that build upon it) there could be non-deterministic errors in some cases (small input collection, not much work per element, see [#82](https://github.com/JuliaFolds2/OhMyThreads.jl/issues/82)). These cases should be fixed now.

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
