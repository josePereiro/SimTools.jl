function test_grad_desc()

    # Vectorize
    for i in 1:10
        target = [10.0 * rand() + 5.0, 10.0 * rand() + 5.0]
        @show target
        x0 = [0.0, 0.0]
        rexps = rand(2:10, 2)
        @show rexps
        maxΔx = 1.0 ./ rexps
        minΔx = 0.0 ./ rexps
        x1 = x0 .+ maxΔx .* 0.1
        gdth = 1e-5
        maxiter = 50000

        function up_fun(gdmodel) 
            xs = SimTools.gd_value(gdmodel)
            xs .^ rexps
        end

        gdmodel = SimTools.grad_desc_vec(up_fun; 
            target, x0, x1, minΔx, maxΔx, gdth, maxiter, 
        )
        @show gdmodel.ϵi
        @show gdmodel.iter
        @show up_fun(gdmodel)
        @test all(isapprox.(up_fun(gdmodel), target; atol = 1e-3))
        println()
    end

    # Scalar
    @testset begin
        for i in 1:10
            target = 10.0 * rand() + 5.0
            @show target
            x0 = 0.0
            rexp = rand(1:10)
            @show rexp
            maxΔx = 1.0 / rexp
            x1 = x0 + maxΔx * 0.1
            maxiter = 1e4
            gdth = 1e-5

            function up_fun(gdmodel) 
                x = SimTools.gd_value(gdmodel)
                x ^ rexp
            end
            gdmodel = SimTools.grad_desc(up_fun; 
                target, x0, x1, maxΔx, gdth, maxiter
            )
            @show gdmodel.ϵi
            @show gdmodel.iter
            @show up_fun(gdmodel)
            @test all(isapprox.(up_fun(gdmodel), target; atol = 1e-3))
            println()
        end
    end

end
test_grad_desc()