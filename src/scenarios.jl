function create_historical_scenarios(container:: FXForwardMarketDataContainer; valuation_date:: Union{Date, Nothing}=nothing, time_horizon:: Integer = 1, lookback:: Integer = 250)

    scenario_dates_raw = collect(keys(first(container.fx_forward_curves).second.curves))
    if valuation_date === nothing
        idx = length(scenario_dates_raw)
    else
        idx = findlast(scenario_dates_raw .<= valuation_date)
    end
    scenario_dates = @view scenario_dates_raw[1:idx]

    fx_scenarios = Dict(key => _calculate_returns(val, time_horizon, lookback, scenario_dates, idx) 
        for (key, val) in pairs(container.fx_forward_curves))

    disc_scenarios = Dict(key => _calculate_returns(val, time_horizon, lookback, scenario_dates, idx) 
        for (key, val) in pairs(container.discount_curves))

    return FXForwardMarketDataContainer(fx_scenarios, disc_scenarios)
end

function _calculate_returns(ts:: T, time_horizon:: Integer, lookback:: Integer, ts_dates, idx:: Int) where {T <: AbstractTimeSeries}

    ts_values_raw = collect(values(ts.curves))
    ts_values = @view ts_values_raw[1:idx]

    base_scenario = last(ts_values)
    values_in_lookback = @view ts_values[end-lookback-time_horizon:end-1] # excluding base scenario

    shifts_raw = values_in_lookback ./ lag(values_in_lookback, time_horizon)
    shifts = [x for x in shifts_raw if !ismissing(x)] # the lag function adds `missing` values at the beginning of the time series, they are removed here.

    scenarios = shifts .* base_scenario
    push!(scenarios, base_scenario) # last scenario is base scenario

    # the scenarios are from the end of the time period
    scenario_dates =  ts_dates[end-length(scenarios)+1:end]

    return T(SortedDict(scenario_dates .=> scenarios))

end
