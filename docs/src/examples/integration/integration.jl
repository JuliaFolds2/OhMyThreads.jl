# # Trapezoidal Integration
#

# Function to be integrated (from 0 to 1). The analytic result is π.

f(x) = 4 * √(1 - x^2)

# Integration routine

"Evaluate definite integral (from `a` to `b`) by using the trapezoidal rule."
function trapezoidal(a, b, n, h)
    y = (f(a) + f(b)) / 2.0
    for i in 1:n-1
        x = a + i * h
        y = y + f(x)
    end
    return y * h
end

using Base.Threads: nthreads

N = 10_000

function integrate_parallel(N)
    # compute local integration interval etc.
    h     = 1.0 / N
    a_loc = [i * n_loc * h for i in 0:nthreads()-1]
    b_loc = a_loc + n_loc * h

    result = tmapreduce(+, ...) do
        trapezoidal(a_loc, b_loc, n, h)
    end

    res_loc = trapezoidal(a_loc, b_loc, n_loc, h)

    println("π (numerical integration) ≈ ", res)
end


# perform local integration
res_loc = trapezoidal(a_loc, b_loc, n_loc, h)

# parallel reduction
res = MPI.Reduce(res_loc, +, comm)

# print result
if 0 == rank
    @printf("π (numerical integration) ≈ %20.16f\\n", res)
end
