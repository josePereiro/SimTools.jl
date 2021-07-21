using SimulationUtils
using Test

@testset "SimulationUtils.jl" begin
    include("bisection_search_tests.jl")
    include("grad_desc_tests.jl")
    include("OnDiskMonitor_tests.jl")
end