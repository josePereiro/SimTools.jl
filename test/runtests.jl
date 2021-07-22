using SimTools
using Test

@testset "SimTools.jl" begin
    include("bisection_search_tests.jl")
    include("grad_desc_tests.jl")
    include("OnDiskMonitor_tests.jl")
end