```@meta
EditURL = "juliaset.jl"
```

# Julia Set

In this example, we will compute an image of the
[Julia set](https://en.wikipedia.org/wiki/Julia_set) in parallel. We will explore
the `schedule` and `nchunks` options that can be used to get load balancing.

The value of a single pixel of the Julia set, which corresponds to a point in the
complex number plane, can be computed by the following iteration procedure.

````julia
function _compute_pixel(i, j, n; max_iter = 255, c = -0.79 + 0.15 * im)
    x = -2.0 + (j - 1) * 4.0 / (n - 1)
    y = -2.0 + (i - 1) * 4.0 / (n - 1)

    z = x + y * im
    iter = max_iter
    for k in 1:max_iter
        if abs2(z) > 4.0
            iter = k - 1
            break
        end
        z = z^2 + c
    end
    return iter
end
````

````
_compute_pixel (generic function with 1 method)
````

Note that the value of the pixel is the number of performed iterations for the
corresponding complex input number. Hence, the computational **workload is non-uniform**.

## Sequential computation

In our naive implementation, we just loop over the dimensions of the image matrix and call
the pixel kernel above.

````julia
function compute_juliaset_sequential!(img)
    N = size(img, 1)
    for j in 1:N
        for i in 1:N
            img[i, j] = _compute_pixel(i, j, N)
        end
    end
    return img
end

N = 2000
img = zeros(Int, N, N)
compute_juliaset_sequential!(img);
````

Let's look at the result

````julia
using Plots
p = heatmap(img)
````
![](juliaset-8.png)

## Parallelization

The Julia set computation above is a `map!` operation: We apply some function to each
element of the array. Hence, we can use `tmap!` for parallelization. We use
`CartesianIndices` to map between linear and two-dimensional cartesian indices.

````julia
using OhMyThreads: tmap!

function compute_juliaset_parallel!(img; kwargs...)
    N = size(img, 1)
    cart = CartesianIndices(img)
    tmap!(img, eachindex(img); kwargs...) do idx
        c = cart[idx]
        _compute_pixel(c[1], c[2], N)
    end
    return img
end

N = 2000
img = zeros(Int, N, N)
compute_juliaset_parallel!(img);
p = heatmap(img)
````
![](juliaset-10.png)

## Benchmark

Let's benchmark the variants above.

````julia
using BenchmarkTools
using Base.Threads: nthreads

N = 2000
img = zeros(Int, N, N)

@btime compute_juliaset_sequential!($img) samples=10 evals=3;
@btime compute_juliaset_parallel!($img) samples=10 evals=3;
````

````
  138.377 ms (0 allocations: 0 bytes)
  63.707 ms (39 allocations: 3.30 KiB)

````

As hoped, the parallel implementation is faster. But can we improve the performance
further?

### Tuning `nchunks`

As stated above, the per-pixel computation is non-uniform. Hence, we might benefit from
load balancing. The simplest way to get it is to increase `nchunks` to a value larger
than `nthreads`. This divides the overall workload into smaller tasks than can be
dynamically distributed among threads (by Julia's scheduler) to balance the per-thread
load.

````julia
@btime compute_juliaset_parallel!($img; schedule=:dynamic, nchunks=N) samples=10 evals=3;
````

````
  32.000 ms (12013 allocations: 1.14 MiB)

````

Note that if we opt out of dynamic scheduling and set `schedule=:static`, this strategy
doesn't help anymore (because chunks are naively distributed up front).

````julia
@btime compute_juliaset_parallel!($img; schedule=:static, nchunks=N) samples=10 evals=3;
````

````
  63.439 ms (42 allocations: 3.37 KiB)

````

---

*This page was generated using [Literate.jl](https://github.com/fredrikekre/Literate.jl).*

