module Tools

using Base.Threads: nthreads, threadpoolsize

"""
Returns the thread id of the `n`th Julia thread in the `:default` threadpool.
"""
@inline function nthtid(n)
    @static if VERSION < v"1.9"
        @boundscheck 1 <= n <= nthreads()
        return n
    else
        @boundscheck 1 <= n <= nthreads(:default)
        return n + threadpoolsize(:interactive) # default threads after interactive threads
    end
end

end # Tools
