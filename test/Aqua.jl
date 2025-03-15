using Aqua

@testset "Aqua.jl" begin
  Aqua.test_all(
    OhMyThreads;
    # ambiguities=(exclude=[SomePackage.some_function], broken=true),
    # stale_deps=(ignore=[SomePackage],),
    deps_compat=(;ignore,),
    # piracies=false,
    persistent_tasks=false,
  )
end
