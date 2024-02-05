```@meta
EditURL = "tls.jl"
```

````julia
using OhMyThreads: TaskLocalValue, tmap, chunks
using LinearAlgebra: mul!, BLAS
using Base.Threads: nthreads, @spawn

function matmulsums(As, Bs)
    N = size(first(As), 1)
    C = Matrix{Float64}(undef, N, N)
    map(As, Bs) do A, B
        mul!(C, A, B)
        sum(C)
    end
end

function matmulsums_race(As, Bs)
    N = size(first(As), 1)
    C = Matrix{Float64}(undef, N, N)
    tmap(As, Bs) do A, B
        mul!(C, A, B)
        sum(C)
    end
end

function matmulsums_naive(As, Bs)
    N = size(first(As), 1)
    tmap(As, Bs) do A, B
        C = Matrix{Float64}(undef, N, N)
        mul!(C, A, B)
        sum(C)
    end
end

function matmulsums_tls(As, Bs)
    N = size(first(As), 1)
    storage = TaskLocalValue{Matrix{Float64}}(() -> Matrix{Float64}(undef, N, N))
    tmap(As, Bs) do A, B
        C = storage[]
        mul!(C, A, B)
        sum(C)
    end
end

function matmulsums_manual(As, Bs)
    N = size(first(As), 1)
    tasks = map(chunks(As; n = nthreads())) do idcs
        @spawn begin
            local C = Matrix{Float64}(undef, N, N)
            local results = Vector{Float64}(undef, length(idcs))
            @inbounds for (i, idx) in enumerate(idcs)
                mul!(C, As[idx], Bs[idx])
                results[i] = sum(C)
            end
            results
        end
    end
    reduce(vcat, fetch.(tasks))
end

BLAS.set_num_threads(1) # to avoid potential oversubscription

As = [rand(1024, 1024) for _ in 1:64]
Bs = [rand(1024, 1024) for _ in 1:64]

res = matmulsums(As, Bs)
res_race = matmulsums_race(As, Bs)
res_naive = matmulsums_naive(As, Bs)
res_tls = matmulsums_tls(As, Bs)
res_manual = matmulsums_manual(As, Bs)

res ≈ res_race
res ≈ res_naive
res ≈ res_tls
res ≈ res_manual

using BenchmarkTools

@btime matmulsums($As, $Bs);
@btime matmulsums_naive($As, $Bs);
@btime matmulsums_tls($As, $Bs);
@btime matmulsums_manual($As, $Bs);
````

````
  3.107 s (3 allocations: 8.00 MiB)
  686.432 ms (174 allocations: 512.01 MiB)
  792.403 ms (67 allocations: 40.01 MiB)
  684.626 ms (51 allocations: 40.00 MiB)

````

---

*This page was generated using [Literate.jl](https://github.com/fredrikekre/Literate.jl).*

