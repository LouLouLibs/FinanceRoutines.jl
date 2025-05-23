@testset "Importing Fama-French factors from Ken French library" begin

        import Dates


        df_FF3_annual = FinanceRoutines.import_FF3(frequency=:annual);
        @test names(df_FF3_annual) == ["datey", "mktrf", "smb", "hml",  "rf"]
        @test nrow(df_FF3_annual) >= Dates.year(Dates.today()) - 1926 - 1


        df_FF3_monthly = FinanceRoutines.import_FF3(frequency=:monthly);
        @test names(df_FF3_monthly) == ["datem", "mktrf", "smb", "hml",  "rf"]
        @test nrow(df_FF3_monthly) >= (Dates.year(Dates.today()) - 1926 - 1) * 12

        df_FF3_daily = FinanceRoutines.import_FF3(frequency=:daily);
        @test names(df_FF3_daily) == ["date", "mktrf", "smb", "hml",  "rf"]
        @test nrow(df_FF3_daily) >= 25_900 & nrow(df_FF3_daily) <= 26_500
    

end
