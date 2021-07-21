function is_stationary(v, th, w)
    length(v) < w && return false
    @views pv = v[end - w + 1:end]
    m = Statistics.mean(pv)
    m = iszero(m) ? one(m) : m
    s = Statistics.std(pv)
    return s <= abs(m) * th
end