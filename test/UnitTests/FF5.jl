@testset "Importing Fama-French 5 factors and Momentum" begin

    import Dates

    # FF5 monthly
    df_FF5_monthly = import_FF5(frequency=:monthly)
    @test names(df_FF5_monthly) == ["datem", "mktrf", "smb", "hml", "rmw", "cma", "rf"]
    @test nrow(df_FF5_monthly) >= (Dates.year(Dates.today()) - 1963 - 1) * 12

    # FF5 annual
    df_FF5_annual = import_FF5(frequency=:annual)
    @test names(df_FF5_annual) == ["datey", "mktrf", "smb", "hml", "rmw", "cma", "rf"]
    @test nrow(df_FF5_annual) >= Dates.year(Dates.today()) - 1963 - 2

    # FF5 daily
    df_FF5_daily = import_FF5(frequency=:daily)
    @test names(df_FF5_daily) == ["date", "mktrf", "smb", "hml", "rmw", "cma", "rf"]
    @test nrow(df_FF5_daily) >= 15_000

    # Momentum monthly
    df_mom_monthly = import_FF_momentum(frequency=:monthly)
    @test "mom" in names(df_mom_monthly)
    @test nrow(df_mom_monthly) > 1000

    # Momentum annual
    df_mom_annual = import_FF_momentum(frequency=:annual)
    @test "mom" in names(df_mom_annual)
    @test nrow(df_mom_annual) > 90

    # Momentum daily
    df_mom_daily = import_FF_momentum(frequency=:daily)
    @test "mom" in names(df_mom_daily)
    @test nrow(df_mom_daily) > 24_000

end
