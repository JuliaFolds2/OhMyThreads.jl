#!/usr/bin/env sh
#=
julia --project -t 5 $0 $@
exit
# =#

const reporoot = joinpath(@__DIR__, "../../..")
const repourl = "https://github.com/JuliaFolds2/OhMyThreads.jl/blob/main/docs"

using Literate
using Pkg

dirs = filter(isdir, readdir())
if length(ARGS) > 0
    dirs = ARGS
end
@show dirs

for d in dirs
    println("directory: ", d)
    cd(d) do
        Pkg.activate(".")
        Pkg.instantiate()
        jlfiles = filter(endswith(".jl"), readdir())
        for f in jlfiles
            Literate.markdown(
                f,
                repo_root_url = repourl,
                execute=true;
                # config=Dict("image_formats" => [(MIME"image/png", ".png")])
            )
        end
    end
end