using MarketRiskPrototype
using Test
using Curves: Curve, Tenor, @t_str
using CurrencyAmounts: @currencies, CurrencyAmount, Currency
using Dates

@testset "MarketRiskPrototype.jl" begin

    @currencies EUR, USD, GBP

    dates = [Date("2020-06-01"), Date("2020-06-02"), Date("2020-06-03"), Date("2020-06-04")]

    fx_curve_1 = Curve([t"2D", t"1W", t"1M", t"3M", t"6M", t"1Y"], [5.5, 5.7, 5.8, 6.1, 6.5, 7.0].*USD./EUR)
    fx_curve_2 = Curve([t"2D", t"1M", t"2M", t"3M", t"6M", t"1Y"], [5.2, 5.4, 5.5, 6.3, 6.9, 7.4].*USD./EUR)

    usd_eur_fx_time_series = FXForwardTimeSeries(EUR, USD, dates, [fx_curve_1, fx_curve_2, fx_curve_1, fx_curve_2])
    @test usd_eur_fx_time_series isa MarketRiskPrototype.AbstractTimeSeries
    
    disc_curve_1 = Curve([t"2D", t"1M", t"2M", t"3M", t"6M", t"1Y"], [0.99, 0.98, 0.96, 0.95, 0.93, 0.9])
    disc_curve_2 = Curve([t"2D", t"1M", t"2M", t"3M", t"6M", t"1Y"], [0.98, 0.97, 0.955, 0.945, 0.925, 0.91])

    usd_disc_time_series = DiscountTimeSeries(USD, dates, [disc_curve_1, disc_curve_2, disc_curve_1, disc_curve_2])
    @test usd_disc_time_series isa MarketRiskPrototype.AbstractTimeSeries

    fx_curve_1b = Curve([t"2D", t"1W", t"1M", t"3M", t"6M", t"1Y"], 0.5.*[5.5, 5.7, 5.8, 6.1, 6.5, 7.0].*EUR./GBP)
    fx_curve_2b = Curve([t"2D", t"1M", t"2M", t"3M", t"6M", t"1Y"], 0.5.*[5.2, 5.4, 5.5, 6.3, 6.9, 7.4].*EUR./GBP)

    eur_gbp_fx_time_series = FXForwardTimeSeries(GBP, EUR, dates, [fx_curve_1b, fx_curve_2b, fx_curve_1b, fx_curve_2b])
    
    disc_curve_1b = Curve([t"2D", t"1M", t"2M", t"3M", t"6M", t"1Y"], 0.95.*[0.99, 0.98, 0.96, 0.95, 0.93, 0.9])
    disc_curve_2b = Curve([t"2D", t"1M", t"2M", t"3M", t"6M", t"1Y"], 0.95.*[0.98, 0.97, 0.955, 0.945, 0.925, 0.91])

    eur_disc_time_series = DiscountTimeSeries(EUR, dates, [disc_curve_1b, disc_curve_2b, disc_curve_1b, disc_curve_2b])

    usd_eur_specific_market_data = MarketRiskPrototype.SpecificFXForwardMarketData(EUR, USD, usd_eur_fx_time_series, usd_disc_time_series)
    @test usd_eur_specific_market_data isa MarketRiskPrototype.AbstractProductSpecificMarketData

    market_data_container = FXForwardMarketDataContainer([usd_eur_fx_time_series, eur_gbp_fx_time_series], [usd_disc_time_series, eur_disc_time_series])
    @test market_data_container isa MarketRiskPrototype.AbstractMarketDataContainer
    @test length(market_data_container.fx_forward_curves) == 2 && length(market_data_container.discount_curves) == 2

    fx_forward_1 = FXForward(100000.0EUR, USD, 2.0USD/EUR, t"3M")
    @test fx_forward_1 isa MarketRiskPrototype.AbstractProduct

    fx_forward_2 = FXForward(100000.0GBP, EUR, 1.5EUR/GBP, t"2M")
    fx_forward_3 = FXForward(100000.0USD, EUR, 0.7EUR/USD, t"3M")

    market_data_recoverd = get_specific_market_data(fx_forward_1, market_data_container)
    @test usd_eur_specific_market_data == market_data_recoverd

    pv = price(fx_forward_1, market_data_container, dates[1])
    @test pv < 0USD

    pv2 = price(fx_forward_2, market_data_container, dates[2])
    @test pv2 < 0EUR

    pv3 = price(fx_forward_3, market_data_container, dates[1])
    @test pv != 0EUR
    
    all_trades = [fx_forward_1, fx_forward_2, fx_forward_3]

    # to calculate pv for multiple trades, just broadcast:
    pv_all_trades = price.(all_trades, market_data_container, dates[1])
    @test length(pv_all_trades) == 3

    pvs = price_time_series(fx_forward_1, market_data_container)
    @test length(pvs) == 4

    # to calculate time series over multiple trades, just broadcast:
    pvs_all_trades = price_time_series.(all_trades, market_data_container)
    @test length(pvs_all_trades) == 3

    var = value_at_risk(pvs .- pv, 0.9)
    @test var isa CurrencyAmount

    shifted_returns = create_historical_scenarios(market_data_container; time_horizon=1, lookback=2)
    @test shifted_returns isa FXForwardMarketDataContainer

    pvs_shifted = price_time_series(fx_forward_1, shifted_returns)
    @test length(pvs_shifted) == 3
    @test pvs_shifted[1] isa CurrencyAmount

    pls = calculate_scenario_pls(fx_forward_1, shifted_returns)
    @test pls isa Vector{CurrencyAmount{Float64, Currency{:USD}}}
    @test length(pls) == 2

    shifted_returns2 = create_historical_scenarios(market_data_container; time_horizon=1, lookback=1, valuation_date=Date("2020-06-03"))
    pvs_shifted2 = price_time_series(fx_forward_1, shifted_returns2)
    @test length(pvs_shifted2) == 2

    var2 = value_at_risk.(all_trades, market_data_container, Date("2020-06-03"); time_horizon=1, lookback=1)
    @test var2 isa Vector{<: CurrencyAmount}
    @test length(var2) == 3

    spot_rates = get_spot_rates(market_data_container)
    var3 = value_at_risk(all_trades, market_data_container, spot_rates, Date("2020-06-03"); time_horizon=1, lookback=1)

end