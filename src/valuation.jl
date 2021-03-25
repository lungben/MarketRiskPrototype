"""
Valuation of a product for given market data
"""
function price end

# product generic
function price(product:: AbstractProduct, container:: AbstractMarketDataContainer, valuation_date:: Date)
    market_data = get_specific_market_data(product, container)
    return price(product, market_data, valuation_date)
end

# product specific because of different market data requirements
function price(product:: FXForward, market_data:: SpecificFXForwardMarketData, valuation_date:: Date)
    fx_forward_curves = market_data.fx_forward_curves
    discount_curves = market_data.discount_curves
    return price(product, fx_forward_curves, discount_curves, valuation_date; flip_fx_direction=market_data.flip_fx_direction)
end

function price(product:: FXForward, fx_forward_curves:: FXForwardTimeSeries, discount_curves:: DiscountTimeSeries, valuation_date:: Date; flip_fx_direction=false)
    fx_forward_curve = fx_forward_curves[valuation_date]
    discount_curve = discount_curves[valuation_date]
    return price(product, fx_forward_curve, discount_curve; flip_fx_direction=flip_fx_direction)
end

function price(product:: FXForward, fx_forward_curve:: Curve, discount_curve:: Curve; flip_fx_direction=false)
    payoff = product.notional_base_currency * product.forward_fx_rate
    interpolated_fx_forward_rate = interpolate(product.tenor, fx_forward_curve)
    par_payoff = flip_fx_direction ? product.notional_base_currency / interpolated_fx_forward_rate : product.notional_base_currency * interpolated_fx_forward_rate
    pv = (payoff - par_payoff) * interpolate(product.tenor, discount_curve)
    return pv
end

"""
Prices a complete time series of a product
"""
function price_time_series(product:: AbstractProduct, container:: AbstractMarketDataContainer)
    market_data = get_specific_market_data(product, container)
    return price_time_series(product, market_data)
end

function price_time_series(product:: FXForward, market_data:: SpecificFXForwardMarketData)
    fx_forward_curves = values(market_data.fx_forward_curves.curves)
    discount_curves = values(market_data.discount_curves.curves)
    pvs = [price(product, fx_curve, discount_curve; flip_fx_direction=market_data.flip_fx_direction) for (fx_curve, discount_curve) in zip(fx_forward_curves, discount_curves)]        
    return pvs
end
