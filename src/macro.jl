function _kwarg_to_tuple(ex)
    ex.head != :(=) &&
        throw(ArgumentError("Invalid keyword argument. Doesn't contain '='."))
    name, val = ex.args
    !(name isa Symbol) &&
        throw(ArgumentError("First part of keyword argument isn't a symbol."))
    val isa QuoteNode && (val = val.value)
    (name, val)
end

macro threaded(args...)
    forex = last(args)
    kwexs = args[begin:(end - 1)]
    scheduler = DynamicScheduler()
    reducer = nothing
    for ex in kwexs
        name, val = _kwarg_to_tuple(ex)
        if name == :scheduler
            if val == :dynamic
                scheduler = DynamicScheduler()
            elseif val == :static
                scheduler = StaticScheduler()
            elseif val == :greedy
                scheduler = GreedyScheduler()
            else
                scheduler = val
            end
        elseif name == :reduce
            reducer = val
        else
            throw(ArgumentError("Unknown keyword argument: $name"))
        end
    end

    if forex.head != :for
        throw(ErrorException("Expected for loop after `@threaded`."))
    else
        it = forex.args[1]
        itvar = it.args[1]
        itrng = it.args[2]
        forbody = forex.args[2]
    end

    lbi = findfirst(forbody.args) do arg
        arg isa Expr && arg.head == :macrocall && arg.args[1] == Symbol("@tasklocal")
    end
    if !isnothing(lbi)
        assignment_ex = forbody.args[lbi].args[3]
        if assignment_ex.head != :(=)
            throw(ErrorException("Wrong usage of @tasklocal. Expected assignment, e.g. `A::Matrix{Float} = rand(2,2)`."))
        end
        left_ex = assignment_ex.args[1]
        if left_ex isa Symbol || left_ex.head != :(::)
            throw(ErrorException("Wrong usage of @tasklocal. Expected typed assignment, e.g. `A::Matrix{Float} = rand(2,2)`."))
        end
        tls_sym = left_ex.args[1]
        tls_type = left_ex.args[2]
        tls_def = assignment_ex.args[2]
        tls_storage = gensym()
        tlsinit = quote
            $(tls_storage) = OhMyThreads.TaskLocalValue{$tls_type}(() -> $(tls_def))
        end
        tlsblock = quote
            $(tls_sym) = $(tls_storage)[]
        end
        deleteat!(forbody.args, lbi)
    else
        tlsinit = nothing
        tlsblock = nothing
    end

    q = if isnothing(reducer)
        quote
            $(tlsinit)
            OhMyThreads.tforeach($(itrng); scheduler = $(scheduler)) do $(itvar)
                $(tlsblock)
                $(forbody)
            end
        end
    else
        quote
            $(tlsinit)
            OhMyThreads.tmapreduce(
                $(reducer), $(itrng); scheduler = $(scheduler)) do $(itvar)
                $(tlsblock)
                $(forbody)
            end
        end
    end
    esc(q)
end
