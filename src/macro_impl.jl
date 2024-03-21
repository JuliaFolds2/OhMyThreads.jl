using OhMyThreads.Tools: OnlyOneRegion, try_enter!
using OhMyThreads.Tools: SimpleBarrier

function tasks_macro(forex)
    if forex.head != :for
        throw(ErrorException("Expected a for loop after `@tasks`."))
    else
        if forex.args[1].head != :(=)
            # this'll catch cases like
            # @tasks for _ ∈ 1:10, _ ∈ 1:10
            #     body
            # end
            throw(ErrorException("`@tasks` currently only supports a single threaded loop, got $(forex.args[1])"))
        end
        it = forex.args[1]
        itvar = it.args[1]
        itrng = it.args[2]
        forbody = forex.args[2]
    end

    settings = Settings()

    # Escape everything in the loop body that is not used in conjuction with one of our
    # "macros", e.g. @set or @local. Code inside of these macro blocks will be escaped by
    # the respective "macro" handling functions below.
    for i in findall(forbody.args) do arg
        !(arg isa Expr && arg.head == :macrocall && arg.args[1] == Symbol("@set")) &&
            !(arg isa Expr && arg.head == :macrocall && arg.args[1] == Symbol("@local")) &&
            !(arg isa Expr && arg.head == :macrocall &&
              arg.args[1] == Symbol("@only_one")) &&
            !(arg isa Expr && arg.head == :macrocall &&
              arg.args[1] == Symbol("@one_by_one")) &&
            !(arg isa Expr && arg.head == :macrocall && arg.args[1] == Symbol("@barrier"))
    end
        forbody.args[i] = esc(forbody.args[i])
    end

    locals_before, locals_names = _maybe_handle_atlocal_block!(forbody.args)
    tls_names = isnothing(locals_before) ? [] : map(x -> x.args[1], locals_before)
    _maybe_handle_atset_block!(settings, forbody.args)
    setup_onlyone_blocks = _maybe_handle_atonlyone_blocks!(forbody.args)
    setup_onebyone_blocks = _maybe_handle_atonebyone_blocks!(forbody.args)
    setup_barriers = _maybe_handle_atbarriers!(forbody.args, settings)

    itrng = esc(itrng)
    itvar = esc(itvar)

    make_mapping_function = if isempty(tls_names)
        :(local function mapping_function($itvar,)
            $(forbody)
        end)

    else
        :(local mapping_function = WithTaskLocals(($(tls_names...),)) do ($(locals_names...),)
            function mapping_function_local($itvar,)
                $(forbody)
            end
        end)
    end
    q = if isgiven(settings.reducer)
        quote
            $setup_onlyone_blocks
            $setup_onebyone_blocks
            $setup_barriers
            $make_mapping_function
            tmapreduce(mapping_function, $(settings.reducer),
                $(itrng))
        end
    elseif isgiven(settings.collect)
        maybe_warn_useless_init(settings)
        quote
            $setup_onlyone_blocks
            $setup_onebyone_blocks
            $setup_barriers
            $make_mapping_function
            tmap(mapping_function, $(itrng))
        end
    else
        maybe_warn_useless_init(settings)
        quote
            $setup_onlyone_blocks
            $setup_onebyone_blocks
            $setup_barriers
            $make_mapping_function
            tforeach(mapping_function, $(itrng))
        end
    end

    # insert keyword arguments into the function call
    kwexpr = :($(Expr(:parameters)))
    if isgiven(settings.scheduler)
        push!(kwexpr.args, Expr(:kw, :scheduler, settings.scheduler))
    end
    if isgiven(settings.init)
        push!(kwexpr.args, Expr(:kw, :init, settings.init))
    end
    for (k, v) in settings.kwargs
        push!(kwexpr.args, Expr(:kw, k, v))
    end
    insert!(q.args[10].args, 2, kwexpr)

    # wrap everything in a let ... end block
    # and, potentially, define the `TaskLocalValue`s.
    result = :(let
    end)
    push!(result.args[2].args, q)
    if !isnothing(locals_before)
        for x in locals_before
            push!(result.args[1].args, x)
        end
    end

    result
end

function maybe_warn_useless_init(settings)
    isgiven(settings.init) &&
        @warn("The @set init = ... settings won't have any effect because no reduction is performed.")
end

Base.@kwdef mutable struct Settings
    # scheduler::Expr = :(DynamicScheduler())
    scheduler::Union{Expr, QuoteNode, NotGiven} = NotGiven()
    reducer::Union{Expr, Symbol, NotGiven} = NotGiven()
    collect::Union{Bool, NotGiven} = NotGiven()
    init::Union{Expr, Symbol, NotGiven} = NotGiven()
    # kwargs::Vector{Pair{Symbol, Any}} = Pair{Symbol, Any}[]
    kwargs::Dict{Symbol, Any} = Dict{Symbol, Any}()
end

function _maybe_handle_atlocal_block!(args)
    locals_before = nothing
    local_inner = nothing
    tlsidx = findfirst(args) do arg
        arg isa Expr && arg.head == :macrocall && arg.args[1] == Symbol("@local")
    end
    if !isnothing(tlsidx)
        locals_before, local_inner = _unfold_atlocal_block(args[tlsidx].args[3])
        deleteat!(args, tlsidx)
    end
    return locals_before, local_inner
end

function _unfold_atlocal_block(ex)
    locals_before = Expr[]
    locals_names = Expr[]
    if ex.head == :(=)
        localb, localn = _atlocal_assign_to_exprs(ex)
        push!(locals_before, localb)
        push!(locals_names, localn)
    elseif ex.head == :block
        tlsexprs = filter(x -> x isa Expr, ex.args) # skip LineNumberNode
        for x in tlsexprs
            localb, localn = _atlocal_assign_to_exprs(x)
            push!(locals_before, localb)
            push!(locals_names, localn)
        end
    else
        throw(ErrorException("Wrong usage of @local. You must either provide a typed assignment or multiple typed assignments in a `begin ... end` block."))
    end
    return locals_before, locals_names
end

#=
If the TLS doesn't have a declared return type, we're going to use `CC.return_type` to get it
automatically. This would normally be non-kosher, but it's okay here for three reasons:
1) The task local value *only* exists within the function being called, meaning that the worldage
is frozen for the full lifetime of the TLV, so and `eval` can't change the outcome or cause incorrect inference.
2) We do not allow users to *write* to the task local value, they can only retrieve its value, so there's no
potential problems from the type being maximally narrow and then them trying to write a value of another type to it
3) the task local value is not user-observable. we never let the user inspect its type, unless they themselves are
using `code____` tools to inspect the generated code, hence if inference changes and gives a more or less precise
type, there's no observable semantic changes, just performance increases or decreases.
=#
function _atlocal_assign_to_exprs(ex)
    left_ex = ex.args[1]
    tls_def = esc(ex.args[2])
    @gensym tl_storage
    if Base.isexpr(left_ex, :(::))
        tls_sym = esc(left_ex.args[1])
        tls_type = esc(left_ex.args[2])
        local_before = :($(tl_storage) = TaskLocalValue{$tls_type}(() -> $(tls_def)))
    else
        tls_sym = esc(left_ex)
        local_before = :($(tl_storage) = let f = () -> $(tls_def)
            TaskLocalValue{Core.Compiler.return_type(f, Tuple{})}(f)
        end)
    end
    local_name = :($(tls_sym))
    return local_before, local_name
end

function _maybe_handle_atset_block!(settings, args)
    idcs = findall(args) do arg
        arg isa Expr && arg.head == :macrocall && arg.args[1] == Symbol("@set")
    end
    isnothing(idcs) && return # no @set block found
    for i in idcs
        ex = args[i].args[3]
        if ex.head == :(=)
            _handle_atset_single_assign!(settings, ex)
        elseif ex.head == :block
            exprs = filter(x -> x isa Expr, ex.args) # skip LineNumberNode
            _handle_atset_single_assign!.(Ref(settings), exprs)
        else
            throw(ErrorException("Wrong usage of @set. You must either provide an assignment or multiple assignments in a `begin ... end` block."))
        end
    end
    deleteat!(args, idcs)
    # check incompatible settings
    if isgiven(settings.collect) && settings.collect && isgiven(settings.reducer)
        throw(ArgumentError("Specifying both collect and reducer isn't supported."))
    end
end

function _handle_atset_single_assign!(settings, ex)
    if ex.head != :(=)
        throw(ErrorException("Wrong usage of @set. Expected assignment, e.g. `scheduler = StaticScheduler()`."))
    end
    sym = ex.args[1]
    def = ex.args[2]
    if hasfield(Settings, sym)
        if sym == :collect && !(def isa Bool)
            throw(ArgumentError("Setting collect can only be true or false."))
            #TODO support specifying the OutputElementType
        end
        def = def isa Bool ? def : esc(def)
        setfield!(settings, sym, def)
    else
        # push!(settings.kwargs, sym => esc(def))
        settings.kwargs[sym] = esc(def)
    end
end

function _maybe_handle_atonlyone_blocks!(args)
    idcs = findall(args) do arg
        arg isa Expr && arg.head == :macrocall && arg.args[1] == Symbol("@only_one")
    end
    isnothing(idcs) && return # no @only_one blocks
    setup_onlyone_blocks = quote end
    for i in idcs
        body = args[i].args[3]
        @gensym onlyone
        init_onlyone_ex = :($(onlyone) = $(OnlyOneRegion()))
        push!(setup_onlyone_blocks.args, init_onlyone_ex)
        args[i] = quote
            Tools.try_enter!($(onlyone)) do
                $(esc(body))
            end
        end
    end
    return setup_onlyone_blocks
end

function _maybe_handle_atonebyone_blocks!(args)
    idcs = findall(args) do arg
        arg isa Expr && arg.head == :macrocall && arg.args[1] == Symbol("@one_by_one")
    end
    isnothing(idcs) && return # no @one_by_one blocks
    setup_onebyone_blocks = quote end
    for i in idcs
        body = args[i].args[3]
        @gensym onebyone
        init_lock_ex = :($(onebyone) = $(Base.ReentrantLock()))
        push!(setup_onebyone_blocks.args, init_lock_ex)
        args[i] = quote
            $(esc(:lock))($(onebyone)) do
                $(esc(body))
            end
        end
    end
    return setup_onebyone_blocks
end

function _maybe_handle_atbarriers!(args, settings)
    idcs = findall(args) do arg
        arg isa Expr && arg.head == :macrocall && arg.args[1] == Symbol("@barrier")
    end
    isnothing(idcs) && return # no @barrier found
    setup_barriers = quote end
    for i in idcs
        if length(args[i].args) < 3
            !haskey(settings.kwargs, :ntasks) &&
                throw(ErrorException("When using `@barrier`, the number of tasks must be " *
                                     "specified explicitly, e.g. via `@set ntasks=...`. " *
                                     "Alternatively, you can explicitly indicate the " *
                                     "number of tasks the barrier should wait for via `@barrier(n)`."))

            ntasks = settings.kwargs[:ntasks]
        else
            ntasks = esc(args[i].args[3])

            if haskey(settings.kwargs, :ntasks) && ntasks != settings.kwargs[:ntasks]
                @warn("Setting the number of tasks (e.g. `@set ntasks=x`) as well as using `@barrier(y)` can potentially be dangerous, especially for `x != y`, and is thus discouraged.")
            end
        end
        @gensym barrier
        push!(setup_barriers.args, :($(barrier) = $(SimpleBarrier)($ntasks)))
        args[i] = :($(esc(:wait))($(barrier)))
    end
    return setup_barriers
end
