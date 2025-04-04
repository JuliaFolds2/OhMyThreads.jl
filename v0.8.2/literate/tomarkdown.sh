#!/usr/bin/env sh
#=
julia --project -t 10 $0 $@
exit
# =#

const reporoot = joinpath(@__DIR__, "../../..")
const repourl = "https://github.com/JuliaFolds2/OhMyThreads.jl/blob/main/docs"

using Literate
using Pkg

if length(ARGS) == 0
    println("Error: Please provide the names of the folders that you want to compile to markdown. " *
    "Alternatively, you can pass \"all\" as the first argument to compile them all.")
    exit()
else
    if first(ARGS) == "all"
        dirs = filter(isdir, readdir())
    else
        dirs = ARGS
    end
end
@show dirs

for d in dirs
    println("directory: ", d)
    cd(d) do
        Pkg.activate(".")
        Pkg.resolve()
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
