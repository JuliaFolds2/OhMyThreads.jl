# # Trapezoidal Integration
#
# In this example, we want to parallelize the computation of a simple numerical integral
# via the trapezoidal rule. The latter is given by
#
# $\int_{a}^{b}f(x)\,dx \approx h \sum_{i=1}^{N}\frac{f(x_{i-1})+f(x_{i})}{2}.$
#
# The function to be integrated is the following.

f(x) = 4 * √(1 - x^2)

# The analytic result of the definite integral (from 0 to 1) is known to be $\pi$.
#
# ## Sequential
#
# Naturally, we implement the trapezoidal rule as a straightforward, sequential `for` loop.

function trapezoidal(a, b, n; h = (b - a) / n)
    y = (f(a) + f(b)) / 2.0
    for i in 1:(n - 1)
        x = a + i * h
        y = y + f(x)
    end
    return y * h
end

# Let's compute the integral of `f` above and see if we get the expected result.
# For simplicity, we choose `N`, the number of panels used to discretize the integration
# interval, as a multiple of the number of available Julia threads.

using Base.Threads: nthreads
@show nthreads()

N = nthreads() * 1_000_000

# Calling `trapezoidal` we do indeed find the (approximate) value of $\pi$.

trapezoidal(0, 1, N) ≈ π

# ## Parallel
#
# Our strategy is the following: Divide the integration interval among the available
# Julia threads. On each thread, use the sequential trapezoidal rule to compute the partial
# integral.
# It is straightforward to implement this strategy with `tmapreduce`. The `map` part
# is, essentially, the application of `trapezoidal` and the reduction operator is chosen to
# be `+` to sum up the local integrals.

using OhMyThreads

function trapezoidal_parallel(a, b, N)
    n = N ÷ nthreads()
    h = (b - a) / N
    return tmapreduce(+, 1:nthreads()) do i
        local α = a + (i - 1) * n * h
        local β = α + n * h
        trapezoidal(α, β, n; h)
    end
end

# First, we check the correctness of our parallel implementation.
trapezoidal_parallel(0, 1, N) ≈ π

# Then, we benchmark and compare the performance of the sequential and parallel versions.

using BenchmarkTools
@btime trapezoidal(0, 1, $N);
@btime trapezoidal_parallel(0, 1, $N);

# Because the problem is trivially parallel - all threads to the same thing and don't need
# to communicate - we expect an ideal speedup of (close to) the number of available threads.
