@testset "GSW Treasury Yields" begin

    import Dates: Date, year
    import Statistics: mean, std


    # Test data import and basic structure
    @testset "Data Import and Basic Structure" begin
        # Test with original function name (backward compatibility)
        df_GSW = import_gsw_parameters(date_range = (Date("1970-01-01"), Date("1989-12-31")),
            additional_variables=[:SVENF05, :SVENF06, :SVENF07, :SVENF99])
        
        @test names(df_GSW) == ["date", "BETA0", "BETA1", "BETA2", "BETA3", "TAU1", "TAU2", "SVENF05", "SVENF06", "SVENF07"]
        @test nrow(df_GSW) > 0
        @test all(df_GSW.date .>= Date("1970-01-01"))
        @test all(df_GSW.date .<= Date("1989-12-31"))
        
        # Test date range validation
        @test_logs (:warn, "starting date posterior to end date ... shuffling them around") match_mode=:any import_gsw_parameters(date_range = (Date("1990-01-01"), Date("1980-01-01")));
        
        # Test missing data handling (-999 flags)
        @test any(ismissing, df_GSW.TAU2)  # Should have some missing τ₂ values in this period
    end

    # Test GSWParameters struct
    @testset "GSWParameters Struct" begin
        
        # Test normal construction
        params = GSWParameters(5.0, -2.0, 1.5, 0.8, 2.5, 0.5)
        @test params.β₀ == 5.0
        @test params.β₁ == -2.0
        @test params.τ₁ == 2.5
        @test params.τ₂ == 0.5
        
        # Test 3-factor model (missing τ₂, β₃)
        params_3f = GSWParameters(5.0, -2.0, 1.5, missing, 2.5, missing)
        @test ismissing(params_3f.β₃)
        @test ismissing(params_3f.τ₂)
        @test FinanceRoutines.is_three_factor_model(params_3f)
        @test !FinanceRoutines.is_three_factor_model(params)
        
        # Test validation
        @test_throws ArgumentError GSWParameters(5.0, -2.0, 1.5, 0.8, -1.0, 0.5)  # negative τ₁
        @test_throws ArgumentError GSWParameters(5.0, -2.0, 1.5, 0.8, 2.5, -0.5)  # negative τ₂
        
        # Test DataFrame row construction
        df_GSW = import_gsw_parameters(date_range = (Date("1985-01-01"), Date("1985-01-31")))
        if nrow(df_GSW) > 0
            params_from_row = GSWParameters(df_GSW[20, :])
            @test params_from_row isa GSWParameters
        end

    end

    # Test core calculation functions
    @testset "Core Calculation Functions" begin

        params = GSWParameters(5.0, -2.0, 1.5, 0.8, 2.5, 0.5)
        params_3f = GSWParameters(5.0, -2.0, 1.5, missing, 2.5, missing)
        
        # Test yield calculations
        yield_4f = gsw_yield(10.0, params)
        yield_3f = gsw_yield(10.0, params_3f)
        yield_scalar = gsw_yield(10.0, 5.0, -2.0, 1.5, 0.8, 2.5, 0.5)
        
        @test yield_4f isa Float64
        @test yield_3f isa Float64
        @test yield_scalar ≈ yield_4f
        
        # Test price calculations
        price_4f = gsw_price(10.0, params)
        price_3f = gsw_price(10.0, params_3f)
        price_scalar = gsw_price(10.0, 5.0, -2.0, 1.5, 0.8, 2.5, 0.5)
        
        @test price_4f isa Float64
        @test price_3f isa Float64
        @test price_scalar ≈ price_4f
        @test price_4f < 1.0  # Price should be less than face value for positive yields
        
        # Test forward rates
        fwd_4f = gsw_forward_rate(2.0, 3.0, params)
        fwd_scalar = gsw_forward_rate(2.0, 3.0, 5.0, -2.0, 1.5, 0.8, 2.5, 0.5)
        @test fwd_4f ≈ fwd_scalar
        
        # Test vectorized functions
        maturities = [0.25, 0.5, 1, 2, 5, 10, 30]
        yields = gsw_yield_curve(maturities, params)
        prices = gsw_price_curve(maturities, params)
        
        @test length(yields) == length(maturities)
        @test length(prices) == length(maturities)
        @test all(y -> y isa Float64, yields)
        @test all(p -> p isa Float64, prices)
        
        # Test input validation
        @test_throws ArgumentError gsw_yield(-1.0, params)  # negative maturity
        @test_throws ArgumentError gsw_price(-1.0, params)  # negative maturity
        @test_throws ArgumentError gsw_forward_rate(3.0, 2.0, params)  # invalid maturity order
    end

    # Test return calculations
    @testset "Return Calculations" begin

        params_t = GSWParameters(5.0, -2.0, 1.5, 0.8, 2.5, 0.5)
        params_t_minus_1 = GSWParameters(4.9, -1.9, 1.4, 0.9, 2.4, 0.6)
        
        # Test return calculation with structs
        ret_struct = gsw_return(10.0, params_t, params_t_minus_1)
        ret_scalar = gsw_return(10.0, 5.0, -2.0, 1.5, 0.8, 2.5, 0.5,
                                     4.9, -1.9, 1.4, 0.9, 2.4, 0.6)
        
        @test ret_struct ≈ ret_scalar
        @test ret_struct isa Float64
        
        # Test different return types
        ret_log = gsw_return(10.0, params_t, params_t_minus_1, return_type=:log)
        ret_arith = gsw_return(10.0, params_t, params_t_minus_1, return_type=:arithmetic)
        
        @test ret_log ≠ ret_arith  # Should be different
        @test ret_log isa Float64
        @test ret_arith isa Float64
        
        # Test excess returns
        excess_ret = gsw_excess_return(10.0, params_t, params_t_minus_1)
        @test excess_ret isa Float64

    end

    # Test DataFrame wrapper functions (original API)
    @testset "DataFrame Wrappers - Original API Tests" begin

        df_GSW = import_gsw_parameters(date_range = (Date("1970-01-01"), Date("1989-12-31")))
        
        # Test original functions with new names
        FinanceRoutines.add_yields!(df_GSW, 1.0)
        FinanceRoutines.add_prices!(df_GSW, 1.0)
        FinanceRoutines.add_returns!(df_GSW, 2.0, frequency=:daily, return_type=:log)

        
        # Verify columns were created
        @test "yield_1y" in names(df_GSW)
        @test "price_1y" in names(df_GSW)
        @test "ret_2y_daily" in names(df_GSW)
        
        # Test the original statistical analysis
        transform!(df_GSW, :date => (x -> year.(x) .÷ 10 * 10) => :date_decade)
        df_stats = combine(
            groupby(df_GSW, :date_decade),
            :yield_1y => ( x -> mean(skipmissing(x)) ) => :mean_yield,
            :yield_1y => ( x -> sqrt(std(skipmissing(x))) ) => :vol_yield,
            :price_1y => ( x -> mean(skipmissing(x)) ) => :mean_price,
            :price_1y => ( x -> sqrt(std(skipmissing(x))) ) => :vol_price,
            :ret_2y_daily => ( x -> mean(skipmissing(x)) ) => :mean_ret_2y_daily,
            :ret_2y_daily => ( x -> sqrt(std(skipmissing(x))) ) => :vol_ret_2y_daily
        )
        
        # Original tests - should still pass
        @test df_stats[1, :mean_yield] < df_stats[2, :mean_yield]
        @test df_stats[1, :vol_yield] < df_stats[2, :vol_yield]
        @test df_stats[1, :mean_price] > df_stats[2, :mean_price]
        @test df_stats[1, :vol_price] < df_stats[2, :vol_price]
        @test df_stats[1, :mean_ret_2y_daily] < df_stats[2, :mean_ret_2y_daily]
        @test df_stats[1, :vol_ret_2y_daily] < df_stats[2, :vol_ret_2y_daily]
    end

    # Test enhanced DataFrame wrapper functions
    @testset "DataFrame Wrappers - Enhanced API" begin

        df_GSW = import_gsw_parameters(date_range = (Date("1980-01-01"), Date("1985-12-31")))
        
        # Test multiple maturities at once
        FinanceRoutines.add_yields!(df_GSW, [0.5, 1, 2, 5, 10])
        expected_yield_cols = ["yield_0.5y", "yield_1y", "yield_2y", "yield_5y", "yield_10y"]
        @test all(col -> col in names(df_GSW), expected_yield_cols)
        
        # Test multiple prices
        FinanceRoutines.add_prices!(df_GSW, [1, 5, 10], face_value=100.0)
        expected_price_cols = ["price_1y", "price_5y", "price_10y"]
        @test all(col -> col in names(df_GSW), expected_price_cols)
        
        # Test different frequencies
        FinanceRoutines.add_returns!(df_GSW, 5, frequency=:monthly, return_type=:arithmetic)
        @test "ret_5y_monthly" in names(df_GSW)
        
        # Test excess returns
        FinanceRoutines.add_excess_returns!(df_GSW, 10, risk_free_maturity=0.25)
        @test "excess_ret_10y_daily" in names(df_GSW)
        
        # Test that calculations work with missing data
        @test any(!ismissing, df_GSW.yield_1y)
        @test any(!ismissing, df_GSW.price_1y)
    end

    # Test convenience functions
    @testset "Convenience Functions" begin

        params = GSWParameters(5.0, -2.0, 1.5, 0.8, 2.5, 0.5)
        
        # Test curve snapshot with struct
        curve_struct = FinanceRoutines.gsw_curve_snapshot(params)
        @test names(curve_struct) == ["maturity", "yield", "price"]
        @test nrow(curve_struct) == 7  # default maturities
        
        # Test curve snapshot with scalars
        curve_scalar = FinanceRoutines.gsw_curve_snapshot(5.0, -2.0, 1.5, 0.8, 2.5, 0.5)
        @test curve_struct.yield ≈ curve_scalar.yield
        @test curve_struct.price ≈ curve_scalar.price
        
        # Test custom maturities
        custom_maturities = [1, 3, 5, 7, 10]
        curve_custom = FinanceRoutines.gsw_curve_snapshot(params, maturities=custom_maturities)
        @test nrow(curve_custom) == length(custom_maturities)
        @test curve_custom.maturity == custom_maturities
    end

    # Test edge cases and robustness
    @testset "Edge Cases and Robustness" begin
        # Test very short and very long maturities
        params = GSWParameters(5.0, -2.0, 1.5, 0.8, 2.5, 0.5)
        
        yield_short = gsw_yield(0.001, params)  # Very short maturity
        yield_long = gsw_yield(100.0, params)   # Very long maturity
        @test yield_short isa Float64
        @test yield_long isa Float64
        
        # Test with extreme parameter values
        params_extreme = GSWParameters(0.0, 0.0, 0.0, 0.0, 10.0, 20.0)
        yield_extreme = gsw_yield(1.0, params_extreme)
        @test yield_extreme ≈ 0.0  # Should be zero with all β parameters = 0
        
        # Test missing data handling in calculations
        df_with_missing = DataFrame(
            date = [Date("2020-01-01")],
            BETA0 = [5.0], BETA1 = [-2.0], BETA2 = [1.5],
            BETA3 = [missing], TAU1 = [2.5], TAU2 = [missing]
        )
        
        FinanceRoutines.add_yields!(df_with_missing, 10.0)
        @test !ismissing(df_with_missing.yield_10y[1])  # Should work with 3-factor model
    end

    # Test performance and consistency
    @testset "Performance and Consistency" begin
        
        params = GSWParameters(5.0, -2.0, 1.5, 0.8, 2.5, 0.5)
        
        # Test that struct and scalar APIs give identical results
        maturities = [0.25, 0.5, 1, 2, 5, 10, 20, 30]
        
        yields_struct = gsw_yield.(maturities, Ref(params))
        yields_scalar = gsw_yield.(maturities, 5.0, -2.0, 1.5, 0.8, 2.5, 0.5)
        
        @test yields_struct ≈ yields_scalar
        
        prices_struct = gsw_price.(maturities, Ref(params))
        prices_scalar = gsw_price.(maturities, 5.0, -2.0, 1.5, 0.8, 2.5, 0.5)
        
        @test prices_struct ≈ prices_scalar
        
        # Test yield curve monotonicity assumptions don't break
        @test all(diff(yields_struct) .< 5.0)  # No huge jumps in yield curve
    end

    # Test 3-factor vs 4-factor model compatibility
    @testset "3-Factor vs 4-Factor Model Compatibility" begin
        # Create both model types
        params_4f = GSWParameters(5.0, -2.0, 1.5, 0.8, 2.5, 0.5)
        params_3f = GSWParameters(5.0, -2.0, 1.5, missing, 2.5, missing)
        
        # Test that 3-factor model gives reasonable results
        yield_4f = gsw_yield(10.0, params_4f)
        yield_3f = gsw_yield(10.0, params_3f)
        
        @test abs(yield_4f - yield_3f) < 2.0  # Should be reasonably close
        
        # Test DataFrame with mixed model periods
        df_mixed = DataFrame(
            date = [Date("2020-01-01"), Date("2020-01-02")],
            BETA0 = [5.0, 5.1], BETA1 = [-2.0, -2.1], BETA2 = [1.5, 1.4],
            BETA3 = [0.8, missing], TAU1 = [2.5, 2.4], TAU2 = [0.5, missing]
        )
        
        FinanceRoutines.add_yields!(df_mixed, 10.0)
        @test !ismissing(df_mixed.yield_10y[1])  # 4-factor period
        @test !ismissing(df_mixed.yield_10y[2])  # 3-factor period
    end

    @testset "Estimation of Yields (Excel function)" begin

        # Test basic bond_yield calculation
        @test FinanceRoutines.bond_yield(950, 1000, 0.05, 3.5, 2) ≈ 0.0663 atol=1e-3
        # Test bond at par (price = face_value should yield ≈ coupon_rate)
        @test FinanceRoutines.bond_yield(1000, 1000, 0.06, 5.0, 2) ≈ 0.06 atol=1e-4
        # Test premium bond (price > face_value should yield < coupon_rate)
        ytm_premium = FinanceRoutines.bond_yield(1050, 1000, 0.05, 10.0, 2)
        @test ytm_premium < 0.05

        # Test Excel API with provided example
        settlement = Date(2008, 2, 15)
        maturity = Date(2016, 11, 15)
        ytm_excel = FinanceRoutines.bond_yield_excel(settlement, maturity, 0.0575, 95.04287, 100.0, 
                                     frequency=2, basis=0)
        @test ytm_excel ≈ 0.06 atol=5e-3 # this is not exactly same 

        # Test Excel API consistency with direct bond_yield
        years = 8.75  # approximate years between Feb 2008 to Nov 2016
        ytm_direct = FinanceRoutines.bond_yield(95.04287, 100.0, 0.0575, years, 2)
        @test ytm_excel ≈ ytm_direct atol=1e-2

        # Test quarterly frequency
        @test FinanceRoutines.bond_yield(980, 1000, 0.04, 2.0, 4) > 0.04  # discount bond
        # Test annual frequency
        @test FinanceRoutines.bond_yield(1020, 1000, 0.03, 5.0, 1) < 0.03  # premium bond
        # Test case where Brent initially failed due to non-bracketing intervals
        @test FinanceRoutines.bond_yield_excel(Date("2014-04-24"), Date("2015-12-01"), 0.04, 105.46, 100.0, frequency=2) ≈ 0.0057 atol=5e-4
        # Two tests with fractional years
        @test FinanceRoutines.bond_yield_excel(Date("2013-10-08"), Date("2020-09-01"), 0.05, 116.76, 100.0; frequency=2) ≈ 0.0235 atol=5e-4
        @test FinanceRoutines.bond_yield_excel(Date("2014-07-31"), Date("2032-05-15"), 0.05, 114.083, 100.0; frequency=2) ≈ 0.0389 atol=5e-4
    end

end  # @testset "GSW Extended Test Suite"















