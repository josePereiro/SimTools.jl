function bisection_search(f::Function, x0::Vector, x1::Vector, t::Vector; 
        tol::Real = 1e-5, 
        maxiters::Int = 1000,
        verbose = true
    )

    @assert all(x0 .<= x1)
    @assert all(length.([x0, x1, t]) .== length(x0))

    x0, x1 = (x0, x1) .|> deepcopy

    # finding sense
    r0 = f(x0)
    r1 = f(x1)
    @assert length(r0) == length(r1) == length(x0)
    sense = map((x) -> x[1] <= x[2] ? 1.0 : -1.0, zip(r0, r1))
    for (i, (tc, sc, rc0, rc1)) in enumerate(zip(t, sense, r0, r1))
        !(sc*rc0 <= tc <= sc*rc1) && error("target[$i] = $tc not in range: [$(sc*rc0), $(sc*rc1)]")
    end

    verbose && (prog = ProgressThresh(tol, "searching:  "))
    xi = x1
    last_xi = x1
    for it in 1:maxiters
        xi = (x1 - x0)/2 + x0
        ri = f(xi)

        # Assume a constant monotony TODO: rethink this
        foreach(eachindex(x0)) do c
            sense[c] > 0.0 ? 
                ri[c] < t[c] ? (x0[c] = xi[c]) : (x1[c] = xi[c]) :
                ri[c] < t[c] ? (x1[c] = xi[c]) : (x0[c] = xi[c])
        end
        
        error = maximum(abs.(ri - t))
        verbose && update!(prog, error)
        if all(error < tol)
            verbose && finish!(prog)
            return xi
        end
        last_xi = xi
    end
    verbose && finish!(prog)
    return xi
end