function get!push!(d; kwargs...)
    for (k, val) in kwargs
        push!(get!(d, k, []), val)
    end
    d
end