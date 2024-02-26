function _kwarg_to_tuple(ex)
    ex.head != :(=) &&
        throw(ArgumentError("Invalid keyword argument. Doesn't contain '='."))
    name, val = ex.args
    !(name isa Symbol) &&
        throw(ArgumentError("First part of keyword argument isn't a symbol."))
    val isa QuoteNode && (val = val.value)
    (name, val)
end

function _tasklocal_assign_to_exprs(ex)
    if ex.head != :(=)
        throw(ErrorException("Wrong usage of @tasklocal. Expected assignment, e.g. `A::Matrix{Float} = rand(2,2)`."))
    end
    left_ex = ex.args[1]
    if left_ex isa Symbol || left_ex.head != :(::)
        throw(ErrorException("Wrong usage of @tasklocal. Expected typed assignment, e.g. `A::Matrix{Float} = rand(2,2)`."))
    end
    tls_sym = left_ex.args[1]
    tls_type = left_ex.args[2]
    tls_def = ex.args[2]
    @gensym tls_storage
    tlsinit = :($(tls_storage) = OhMyThreads.TaskLocalValue{$tls_type}(() -> $(tls_def)))
    tlsblock = :($(tls_sym) = $(tls_storage)[])
    return tlsinit, tlsblock
end

function _unfold_tasklocal_block(ex)
    tlsinits = Expr[]
    if ex.head == :(=)
        tlsi, tlsblock = _tasklocal_assign_to_exprs(ex)
        push!(tlsinits, tlsi)
    elseif ex.head == :block
        tlsexprs = filter(x -> x isa Expr, ex.args) # skip LineNumberNode
        tlsblock = quote end
        for x in tlsexprs
            tlsi, tlsb = _tasklocal_assign_to_exprs(x)
            push!(tlsinits, tlsi)
            push!(tlsblock.args, tlsb)
        end
    else
        throw(ErrorException("Wrong usage of @tasklocal. You must either provide a typed assignment or multiple typed assignments in a `begin ... end` block."))
    end
    return tlsinits, tlsblock
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
        elseif name == :reducer
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

    tlsinits = nothing
    tlsblock = nothing
    tlsidx = findfirst(forbody.args) do arg
        arg isa Expr && arg.head == :macrocall && arg.args[1] == Symbol("@tasklocal")
    end
    if !isnothing(tlsidx)
        tlsinits, tlsblock = _unfold_tasklocal_block(forbody.args[tlsidx].args[3])
        deleteat!(forbody.args, tlsidx)
    end

    q = if isnothing(reducer)
        quote
            OhMyThreads.tforeach($(itrng); scheduler = $(scheduler)) do $(itvar)
                $(tlsblock)
                $(forbody)
            end
        end
    else
        quote
            OhMyThreads.tmapreduce(
                $(reducer), $(itrng); scheduler = $(scheduler)) do $(itvar)
                $(tlsblock)
                $(forbody)
            end
        end
    end

    result = :(let
    end)
    push!(result.args[2].args, q)
    if !isnothing(tlsinits)
        for x in tlsinits
            push!(result.args[1].args, x)
        end
    end

    esc(result)
end