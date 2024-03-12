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

    locals_before, locals_names = _maybe_handle_atlocal_block!(forbody.args)
    tls_names = isnothing(locals_before) ? [] : map(x -> x.args[1], locals_before)
    _maybe_handle_atset_block!(settings, forbody.args)

    forbody = esc(forbody)
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
    q = if !isnothing(settings.reducer)
        quote
            $make_mapping_function
            tmapreduce(mapping_function, $(settings.reducer), $(itrng); scheduler = $(settings.scheduler))
        end
    elseif settings.collect
        maybe_warn_useless_init(settings)
        quote
            $make_mapping_function
            tmap(mapping_function, $(itrng); scheduler = $(settings.scheduler))
        end
    else
        maybe_warn_useless_init(settings)
        quote
            $make_mapping_function
            tforeach(mapping_function, $(itrng); scheduler = $(settings.scheduler))
        end
    end

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
    !isnothing(settings.init) &&
        @warn("The @set init = ... settings won't have any effect because no reduction is performed.")
end

Base.@kwdef mutable struct Settings
    scheduler::Expr = :(DynamicScheduler())
    reducer::Union{Expr, Symbol, Nothing} = nothing
    collect::Bool = false
    init::Union{Expr, Symbol, Nothing} = nothing
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
            push!(locals_names,  localn)
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
        tls_sym  = esc(left_ex)
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
    if settings.collect && !isnothing(settings.reducer)
        throw(ArgumentError("Specifying both collect and reducer isn't supported."))
    end
end

function _handle_atset_single_assign!(settings, ex)
    if ex.head != :(=)
        throw(ErrorException("Wrong usage of @set. Expected assignment, e.g. `scheduler = StaticScheduler()`."))
    end
    sym = ex.args[1]
    if !hasfield(Settings, sym)
        throw(ArgumentError("Unknown setting \"$(sym)\". Must be ∈ $(fieldnames(Settings))."))
    end
    def = ex.args[2]
    if sym == :collect && !(def isa Bool)
        throw(ArgumentError("Setting collect can only be true or false."))
        #TODO support specifying the OutputElementType
    end
    def = if def isa QuoteNode
        _sym2scheduler(def.value)
    elseif def isa Bool
        def
    else
        esc(def)
    end
    setfield!(settings, sym, def)
end
