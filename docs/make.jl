using Documenter
using OhMyThreads

const ci = get(ENV, "CI", "") == "true"

@info "Generating Documenter.jl site"
makedocs(;
    sitename = "OhMyThreads.jl",
    authors = "Carsten Bauer, Mason Protter",
    modules = [OhMyThreads],
    checkdocs = :exports,
    doctest = false,
    pages = [
        "OhMyThreads" => "index.md",
        "Translation Guide" => "translation.md",
        "Thread-Safe Storage" => "literate/tls/tls.md",
        "Examples" => [
            "Parallel Monte Carlo" => "literate/mc/mc.md",
            "Julia Set" => "literate/juliaset/juliaset.md",
            "Trapezoidal Integration" => "literate/integration/integration.md"
        ],
        # "Explanations" => [
        #     "Task-Based Multithreading" => "explain/taskbasedmt.md",
        # ],
        "API" => [
            "Public API" => "refs/api.md",
            "Experimental" => "refs/experimental.md",
            "Internal" => "refs/internal.md"
        ]
    ],
    repo = "https://github.com/JuliaFolds2/OhMyThreads.jl/blob/{commit}{path}#{line}",
    format = Documenter.HTML(repolink = "https://github.com/JuliaFolds2/OhMyThreads.jl"; collapselevel = 1))

if ci
    @info "Deploying documentation to GitHub"
    deploydocs(;
        repo = "github.com/JuliaFolds2/OhMyThreads.jl.git",
        devbranch = "master",
        push_preview = true)
end
