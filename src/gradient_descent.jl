## ------------------------------------------------------------------------------
# Container
mutable struct GDModel{T}
    # current state
    iter::Int
    xi::T
    fi::T
    ϵi::T
    ϵii::T
    Δx::T
    sense::T
    sense_count::T
    damp::T
    
    # params
    damp_win::Real
    damp_factor::Real
    target::T
    maxΔx::T
    minΔx::T
    maxiter::Int
    gdth::Real
    smooth::Real
    verbose::Bool
end

# constructor
function GDModel(;
        target, 
        maxΔx, minΔx, 
        maxiter = Int(1e4), 
        smooth = 1.0,
        it0 = 1, 
        damp = zero(target) .+ one(eltype(target)),
        damp_win = 4,
        damp_factor = 0.9, # damp reduction factor
        gdth,
        verbose = true,
    )

    iter = Int(it0)
    maxiter = Int(maxiter)
    xi = zero(target)
    fi = zero(target)
    ϵi = zero(target)
    ϵii = zero(target)
    Δx = zero(target)
    sense = zero(target)
    sense_count = zero(target)
    GDModel{typeof(target)}(
        # state
        iter, xi, fi, ϵi, ϵii, Δx, sense, sense_count, damp,
        # params
        damp_win, damp_factor, target, maxΔx, minΔx, maxiter, gdth, smooth, verbose
    )
end

gd_value(gdmodel::GDModel) = gdmodel.xi

## ------------------------------------------------------------------------------
# Vectorize version
function _default_Err_fun(gdmodel::GDModel{T}) where T<:AbstractArray 
    diff = abs.(gdmodel.target - gdmodel.fi)
    norm = ifelse.(iszero.(gdmodel.target), 1.0, abs.(gdmodel.target))
    diff ./ norm
end

_default_break_cond(gdmodel::GDModel{T}) where T<:AbstractArray = 
    maximum(gdmodel.ϵi) < gdmodel.gdth 

function _default_get_step(gdmodel::GDModel{T}) where T<:AbstractArray
    max_step = gdmodel.maxΔx
    correction = ifelse.(gdmodel.ϵi .< gdmodel.smooth, min.(1.0, gdmodel.ϵi), 1.0)
    step = max_step .* correction .* gdmodel.damp
    gdmodel.sense .* clamp.(step, gdmodel.minΔx, gdmodel.maxΔx)
end

function _default_get_sense(gdmodel::GDModel{T}) where T<:AbstractArray 
    Δϵ = gdmodel.ϵi .- gdmodel.ϵii
    zeros = iszero.(Δϵ)
    sense = gdmodel.sense .* -sign.(gdmodel.ϵi .- gdmodel.ϵii)
    if any(zeros)
        rsense = rand(-1:1, length(Δϵ))
        sense = ifelse.(zeros, rsense, sense)
    end
    return sense
end

    
function grad_desc_vec!(f::Function, gdmodel::GDModel{T};
        x0::T, x1::T,
        toshow::Vector = [],
        Err::Function = _default_Err_fun,
        break_cond::Function = _default_break_cond,
        oniter!::Function = (dgmodel) -> false,
        get_sense::Function = _default_get_sense,
        get_step::Function = _default_get_step,
    ) where {T<:AbstractArray}

    # initializing
    gdmodel.xi .= x0
    gdmodel.fi .= f(gdmodel)
    gdmodel.ϵi .= Err(gdmodel)
    break_cond(gdmodel) && return gdmodel

    gdmodel.ϵii .= gdmodel.ϵi
    gdmodel.sense .= ones(length(gdmodel.target))
    gdmodel.Δx .= zero(gdmodel.xi)
    gdmodel.xi .= x1

    prog = ProgressThresh(gdmodel.gdth, "Grad desc: ")
    it0 = gdmodel.iter
    while true

        gdmodel.xi += gdmodel.Δx
        gdmodel.fi .= f(gdmodel)
        gdmodel.ϵi .= Err(gdmodel)
        gdmodel.sense .= get_sense(gdmodel)
        gdmodel.Δx .= get_step(gdmodel)
        
        # callback
        ret = oniter!(gdmodel)
        ret && return gdmodel

        gdmodel.ϵii .= gdmodel.ϵi

        # Damp detection
        if iszero(rem(gdmodel.iter, gdmodel.damp_win))
            isdamping = iszero.(gdmodel.sense_count) 
            gdmodel.damp .= ifelse.(isdamping, gdmodel.damp .*= gdmodel.damp_factor, gdmodel.damp)
            gdmodel.sense_count .= zero(gdmodel.sense_count)
        end
        gdmodel.sense_count .+= gdmodel.sense

        # verbose
        if gdmodel.verbose
            maxϵᵢ = maximum(gdmodel.ϵi)
            update!(prog, maxϵᵢ; showvalues = vcat(
                    [
                        ("it", gdmodel.iter),
                        ("maxϵᵢ", maxϵᵢ),
                        ("ϵᵢ", gdmodel.ϵi),
                        ("sense", gdmodel.sense),
                        ("xᵢ", gdmodel.xi),
                        ("Δxᵢ", gdmodel.Δx),
                        ("t", gdmodel.target),
                        ("fi", gdmodel.fi),
                    ], toshow
                )
            )
        end

        # break condition
        break_cond(gdmodel) && break
        gdmodel.iter >= gdmodel.maxiter &&  break

        gdmodel.iter += 1
    end
    gdmodel.verbose && finish!(prog)

    return gdmodel
end

function grad_desc_vec(f::Function;
        x0::T, x1::T,
        target::T, 
        maxΔx::T = abs.(x0 - x1), 
        minΔx::T = abs.(maxΔx .* 1e-35),
        gdth::Real = 1e-5, 
        smooth::Real = 1.0,
        maxiter = Int(1000), 
        damp = zero(target) .+ one(eltype(target)),
        damp_win = 4,
        damp_factor = 0.9, # damp reduction factor
        it0 = 1, 
        verbose = true,
        kwargs...
    ) where {T<:AbstractArray}

    gdmodel = GDModel(;target, maxΔx, minΔx, maxiter, it0, 
        gdth, smooth, damp, damp_win, damp_factor, verbose
    )
    grad_desc_vec!(f, gdmodel; x0, x1, kwargs...)

end

## ------------------------------------------------------------------------------
# Scalar version
function _default_Err_fun(gdmodel::GDModel{T}) where T<:Real 
    diff = abs(gdmodel.target - gdmodel.fi)
    norm = ifelse(iszero(gdmodel.target), 1.0, abs(gdmodel.target))
    diff / norm
end

_default_break_cond(gdmodel::GDModel{T}) where T<:Real = gdmodel.ϵi < gdmodel.gdth 

function _default_get_step(gdmodel::GDModel{T}) where T<:Real 
    max_step = gdmodel.maxΔx
    correction = (gdmodel.ϵi < gdmodel.smooth) ? min.(1.0, gdmodel.ϵi) : 1.0
    step = max_step * correction * gdmodel.damp
    gdmodel.sense * clamp(step, gdmodel.minΔx, gdmodel.maxΔx)
end

function _default_get_sense(gdmodel::GDModel{T}) where T<:Real 
    Δϵ = gdmodel.ϵi - gdmodel.ϵii
    iszero(Δϵ) ? rand(-1:1) : gdmodel.sense * -sign(gdmodel.ϵi - gdmodel.ϵii)
end

function grad_desc!(f::Function, gdmodel::GDModel{T};
        x0::T, x1::T,
        toshow::Vector = [],
        Err::Function = _default_Err_fun,
        break_cond::Function = _default_break_cond,
        oniter!::Function = (dgmodel) -> false,
        get_sense::Function = _default_get_sense,
        get_step::Function = _default_get_step,
    ) where {T<:Real}

    # initializing
    gdmodel.xi = x0
    gdmodel.fi = f(gdmodel)
    gdmodel.ϵi = Err(gdmodel)
    break_cond(gdmodel) && return gdmodel

    gdmodel.ϵii = gdmodel.ϵi
    gdmodel.sense = one(gdmodel.target)
    gdmodel.Δx = zero(gdmodel.xi)
    gdmodel.xi = x1

    prog = ProgressThresh(gdmodel.gdth, "Grad desc: ")
    it0 = gdmodel.iter
    while true

        gdmodel.xi += gdmodel.Δx
        gdmodel.fi = f(gdmodel)
        gdmodel.ϵi = Err(gdmodel)
        gdmodel.sense = get_sense(gdmodel)
        gdmodel.Δx = get_step(gdmodel)
        
        # callback
        ret = oniter!(gdmodel)
        ret && return gdmodel
        
        if gdmodel.verbose
            update!(prog, gdmodel.ϵi; showvalues = vcat(
                    [
                        ("it", gdmodel.iter),
                        ("ϵᵢ", gdmodel.ϵi),
                        ("sense", gdmodel.sense),
                        ("Δx: min/val/max", (gdmodel.minΔx, gdmodel.Δx, gdmodel.maxΔx)),
                        ("xᵢ", gdmodel.xi),
                        ("t", gdmodel.target),
                        ("fi", gdmodel.fi),
                    ], toshow
                )
            )
        end

        gdmodel.ϵii = gdmodel.ϵi

        # Damp detection
        if iszero(rem(gdmodel.iter, gdmodel.damp_win))
            if iszero(gdmodel.sense_count)
                # Damping detetected
                gdmodel.damp *= gdmodel.damp_factor
            end
            gdmodel.sense_count = 0
        end
        gdmodel.sense_count += gdmodel.sense

        # break condition
        break_cond(gdmodel) && break
        gdmodel.iter >= gdmodel.maxiter &&  break

        gdmodel.iter += 1
    end
    gdmodel.verbose && finish!(prog)

    return gdmodel
end

function grad_desc(f::Function;
        x0::T, x1::T,
        target::T, 
        maxΔx::T = abs(x0 - x1), 
        minΔx::T = abs(maxΔx * 1e-35), 
        smooth = 1.0,
        gdth::Real = 1e-5, 
        maxiter = Int(1000), 
        it0 = 1, 
        damp = 1.0,
        damp_win = 4,
        damp_factor = 0.9, # damp reduction factor
        verbose = true,
        kwargs...
    ) where {T<:Real}

    gdmodel = GDModel(;target, minΔx, maxΔx, maxiter, it0, gdth, 
        damp, damp_win, damp_factor, smooth, verbose
    )
    grad_desc!(f, gdmodel; x0, x1, kwargs...)

end
