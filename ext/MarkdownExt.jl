module MarkdownExt

using Markdown: Markdown, @md_str, term
using OhMyThreads.Implementation: BoxedVariableError

function __init__()
    if isdefined(Base.Experimental, :register_error_hint)
        Base.Experimental.register_error_hint(BoxedVariableError) do io, bve
            println(io)
            println(io)
            term(io, md"""
Capturing boxed variables can be not only slow, but also cause race conditions. 

* If you meant for these variables to be local to each loop iteration and not depend on a variable from an outer scope, you should mark them as `local` inside the closure.
* If you meant to reference a variable from the outer scope, but do not want access to it to be boxed, you can wrap uses of it in a let block, like e.g.
```julia
function foo(x, N)
    if rand(Bool)
    x = 1 # This rebinding of x causes it to be boxed ...
    end
    let x = x # ... Unless we localize it here with the let block 
        @tasks for i in 1:N
            f(x)    
        end
    end
end
```
* OhMyThreads.jl provides a `@localize` macro that automates the above `let` block, i.e. `@localize x f(x)` is the same as `let x=x; f(x) end`
* If these variables are being re-bound inside a `@one_by_one` or `@only_one` block, consider using a mutable `Ref` instead of re-binding the variable.

This error can be bypassed with the `@allow_boxed_captures` macro.
    """)
        end
    end
end 



end
