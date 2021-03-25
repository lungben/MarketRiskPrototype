## Market risk calculation (not product-specific)

function calculate_scenario_pls(pvs:: AbstractVector{<: CurrencyAmount}) 
    base_pv = last(pvs)
    scenario_pvs = (@view pvs[1:end-1]) .- base_pv
    return scenario_pvs
end

function calculate_scenario_pls(product:: AbstractProduct, scenarios:: AbstractMarketDataContainer)
    scenario_pvs = price_time_series(product, scenarios)
    scenario_pls = calculate_scenario_pls(scenario_pvs)
    return scenario_pls
end

function value_at_risk(scenario_pls:: AbstractVector, quantile_value:: Real; alpha=1.0, beta=alpha)
    0.0 < quantile_value < 1.0 || error("quantile must be between 0 and 1")
    var = -quantile(scenario_pls, one(quantile_value)-quantile_value; alpha, beta)
    return var
end

function value_at_risk(product:: AbstractProduct, container:: FXForwardMarketDataContainer, valuation_date:: Date; 
    quantile_value:: Number=0.99, time_horizon:: Integer = 1, lookback:: Integer = 250)

    scenarios = create_historical_scenarios(container; valuation_date, time_horizon, lookback)
    scenario_pls = calculate_scenario_pls(product, scenarios)
    var = value_at_risk(scenario_pls, quantile_value)
    return var
end

function value_at_risk(products:: AbstractVector{<: AbstractProduct}, container:: FXForwardMarketDataContainer, spot_rates:: Dict, valuation_date:: Date; 
    quantile_value:: Number=0.99, time_horizon:: Integer = 1, lookback:: Integer = 250, target_currency:: Currency = Currency{:EUR}())
    scenarios = create_historical_scenarios(container; valuation_date, time_horizon, lookback)

    scenario_pls = calculate_scenario_pls.(products, scenarios)
    scenario_pls_all = sum(convert.(target_currency, x, Ref(values(spot_rates))) for x in scenario_pls)

    var = value_at_risk(scenario_pls_all, quantile_value)
    return var
end

