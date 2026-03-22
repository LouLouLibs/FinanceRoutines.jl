@testset "Portfolio Return Calculations" begin

    import Dates: Date, Month

    # Create test data: 3 stocks, 12 months
    dates = repeat(Date(2020,1,1):Month(1):Date(2020,12,1), inner=3)
    df = DataFrame(
        datem = dates,
        permno = repeat([1, 2, 3], 12),
        ret = rand(36) .* 0.1 .- 0.05,
        mktcap = repeat([100.0, 200.0, 300.0], 12)
    )

    # Equal-weighted returns
    df_ew = calculate_portfolio_returns(df, :ret, :datem; weighting=:equal)
    @test nrow(df_ew) == 12
    @test "port_ret" in names(df_ew)

    # Value-weighted returns
    df_vw = calculate_portfolio_returns(df, :ret, :datem;
                                         weighting=:value, weight_col=:mktcap)
    @test nrow(df_vw) == 12
    @test "port_ret" in names(df_vw)

    # Grouped portfolios (e.g., by size group)
    df.group = repeat([1, 1, 2], 12)
    df_grouped = calculate_portfolio_returns(df, :ret, :datem;
                                              weighting=:value, weight_col=:mktcap,
                                              groups=:group)
    @test nrow(df_grouped) == 24  # 12 months x 2 groups

    # Error cases
    @test_throws ArgumentError calculate_portfolio_returns(df, :ret, :datem; weighting=:value)
    @test_throws ArgumentError calculate_portfolio_returns(df, :ret, :datem; weighting=:foo)

    # Missing handling
    allowmissing!(df, :ret)
    df.ret[1] = missing
    df_ew2 = calculate_portfolio_returns(df, :ret, :datem; weighting=:equal)
    @test nrow(df_ew2) == 12
    @test !ismissing(df_ew2.port_ret[1])  # should compute from non-missing stocks

end
