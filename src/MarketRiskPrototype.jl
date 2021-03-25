module MarketRiskPrototype

export MarketRiskScenarios, FXForward, FXForwardTimeSeries, DiscountTimeSeries, FXForwardMarketDataContainer
export get_specific_market_data, price, value_at_risk, price_time_series, get_spot_rates, create_historical_scenarios
export calculate_scenario_pls

using Curves: Curve, Tenor, interpolate, @t_str
using CurrencyAmounts: Currency, CurrencyAmount, ExchangeRate
using Dates: Date
using Statistics: quantile
using DataStructures: SortedDict
using ShiftedArrays: lag

include("products.jl")
include("market_data.jl")
include("valuation.jl")
include("market_risk.jl")
include("scenarios.jl")

end
