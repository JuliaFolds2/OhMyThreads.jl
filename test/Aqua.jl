using Aqua

@testset "Aqua.jl" begin
  ignore = isdefined(Base, :ScopedValues) ? [:ScopedValues] : []
  Aqua.test_all(
    OhMyThreads;
    # ambiguities=(exclude=[SomePackage.some_function], broken=true),
    stale_deps=(ignore=[:ScopedValues],),
    deps_compat=(;ignore,),
    # piracies=false,
    persistent_tasks=false,
  )
end
