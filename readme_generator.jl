using OhMyThreads

open("README.md", "w+") do io
    println(io, """
# OhMyThreads

#### This package is in very early development and is not yet registered

This is meant to be a simple, unambitious package that provides basic, user-friendly ways of doing 
multithreaded calculations via higher-order functions, with a focus on [data parallelism](https://en.wikipedia.org/wiki/Data_parallelism).

Unlike most JuliaFolds2 packages, it is not built off of [Transducers.jl](https://github.com/JuliaFolds2/Transducers.jl), nor is it a building block of Transducers.jl, instead OhMyThreads is meant to be a simpler, more maintainable, and more accessible alternative to packages like [ThreadsX.jl](https://github.com/tkf/ThreadsX.jl) or [Folds.jl](https://github.com/JuliaFolds2/Folds.jl).

OhMyThreads.jl re-exports the very useful function `chunks` from [ChunkSplitters.jl](https://github.com/m3g/ChunkSplitters.jl), and provides the following functions:
""")
    for sym ∈ (:tmapreduce, :treducemap, :treduce, :tmap, :tmap!, :tforeach, :tcollect)
        println(io, "<details><summary> $sym </summary>\n<p>\n")
        println(io, Base.Docs.doc(Base.Docs.Binding(OhMyThreads, sym)))
        println(io, "\n</details>\n</p>")
        println(io, "\n____________________________\n")
    end
end
