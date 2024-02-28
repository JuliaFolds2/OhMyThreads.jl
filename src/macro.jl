Base.@kwdef mutable struct Settings
    scheduler::Expr = :(DynamicScheduler())
    reducer::Union{Expr, Symbol, Nothing} = nothing
end

macro tasks(args...)
    forex = last(args)
    if forex.head != :for || length(args) > 1
        throw(ErrorException("Expected a for loop after `@tasks`."))
    else
        it = forex.args[1]
        itvar = it.args[1]
        itrng = it.args[2]
        forbody = forex.args[2]
    end

    settings = Settings()

    # kwexs = args[begin:(end - 1)]
    # for ex in kwexs
    #     name, val = _kwarg_to_tuple(ex)
    #     if name == :scheduler
    #         settings.scheduler = val isa Symbol ? _sym2scheduler(val) : val
    #     elseif name == :reducer
    #         settings.reducer = val
    #     else
    #         throw(ArgumentError("Unknown keyword argument: $name"))
    #     end
    # end

    inits_before, init_inner = _maybe_handle_init_block!(forbody.args)
    _maybe_handle_set_block!(settings, forbody.args)

    forbody = esc(forbody)
    itrng = esc(itrng)
    itvar = esc(itvar)

    # @show settings
    q = if isnothing(settings.reducer)
        quote
            tforeach($(itrng); scheduler = $(settings.scheduler)) do $(itvar)
                $(init_inner)
                $(forbody)
            end
        end
    else
        quote
            tmapreduce(
                $(settings.reducer), $(itrng); scheduler = $(settings.scheduler)) do $(itvar)
                $(init_inner)
                $(forbody)
            end
        end
    end

    # wrap everything in a let ... end block
    # and, potentially, define the `TaskLocalValue`s.
    result = :(let
    end)
    push!(result.args[2].args, q)
    if !isnothing(inits_before)
        for x in inits_before
            push!(result.args[1].args, x)
        end
    end

    result
end

function _kwarg_to_tuple(ex)
    ex.head != :(=) &&
        throw(ArgumentError("Invalid keyword argument. Doesn't contain '='."))
    name, val = ex.args
    !(name isa Symbol) &&
        throw(ArgumentError("First part of keyword argument isn't a symbol."))
    val isa QuoteNode && (val = val.value)
    (name, val)
end

function _sym2scheduler(s)
    if s == :dynamic
        :(DynamicScheduler())
    elseif s == :static
        :(StaticScheduler())
    elseif s == :greedy
        :(GreedyScheduler())
    else
        throw(ArgumentError("Unknown scheduler symbol."))
    end
end

function _maybe_handle_init_block!(args)
    inits_before = nothing
    init_inner = nothing
    tlsidx = findfirst(args) do arg
        arg isa Expr && arg.head == :macrocall && arg.args[1] == Symbol("@init")
    end
    if !isnothing(tlsidx)
        inits_before, init_inner = _unfold_init_block(args[tlsidx].args[3])
        deleteat!(args, tlsidx)
    end
    return inits_before, init_inner
end

function _unfold_init_block(ex)
    inits_before = Expr[]
    if ex.head == :(=)
        initb, init_inner = _init_assign_to_exprs(ex)
        push!(inits_before, initb)
    elseif ex.head == :block
        tlsexprs = filter(x -> x isa Expr, ex.args) # skip LineNumberNode
        init_inner = quote end
        for x in tlsexprs
            initb, initi = _init_assign_to_exprs(x)
            push!(inits_before, initb)
            push!(init_inner.args, initi)
        end
    else
        throw(ErrorException("Wrong usage of @init. You must either provide a typed assignment or multiple typed assignments in a `begin ... end` block."))
    end
    return inits_before, init_inner
end

function _init_assign_to_exprs(ex)
    if ex.head != :(=)
        throw(ErrorException("Wrong usage of @init. Expected assignment, e.g. `A::Matrix{Float} = rand(2,2)`."))
    end
    left_ex = ex.args[1]
    if left_ex isa Symbol || left_ex.head != :(::)
        throw(ErrorException("Wrong usage of @init. Expected typed assignment, e.g. `A::Matrix{Float} = rand(2,2)`."))
    end
    tls_sym = esc(left_ex.args[1])
    tls_type = esc(left_ex.args[2])
    tls_def = esc(ex.args[2])
    @gensym tls_storage
    init_before = :($(tls_storage) = OhMyThreads.TaskLocalValue{$tls_type}(() -> $(tls_def)))
    init_inner = :($(tls_sym) = $(tls_storage)[])
    return init_before, init_inner
end

function _maybe_handle_set_block!(settings, args)
    idcs = findall(args) do arg
        arg isa Expr && arg.head == :macrocall && arg.args[1] == Symbol("@set")
    end
    isnothing(idcs) && return # no set block found
    for i in idcs
        ex = args[i].args[3]
        if ex.head == :(=)
            _handle_set_single_assign!(settings, ex)
        elseif ex.head == :block
            exprs = filter(x -> x isa Expr, ex.args) # skip LineNumberNode
            _handle_set_single_assign!.(Ref(settings), exprs)
        else
            throw(ErrorException("Wrong usage of @set. You must either provide an assignment or multiple assignments in a `begin ... end` block."))
        end
    end
    deleteat!(args, idcs)
end

function _handle_set_single_assign!(settings, ex)
    if ex.head != :(=)
        throw(ErrorException("Wrong usage of @set. Expected assignment, e.g. `scheduler = StaticScheduler()`."))
    end
    sym = ex.args[1]
    if !hasfield(Settings, sym)
        throw(ErrorException("Unknown setting \"$(sym)\". Must be ∈ $(fieldnames(Settings))."))
    end
    def = ex.args[2]
    def = if def isa QuoteNode
        _sym2scheduler(def.value)
    else
        esc(def)
    end
    setfield!(settings, sym, def)
end
