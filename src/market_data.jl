
#= 
# Description of Market data model:

1. The highest level are the market data containers, e.g. `FXForwardMarketDataContainer <: AbstractMarketDataContainer`. They store all market data for a whole product class (e.g. FX Forwards) and for the whole time series.
2. The 2nd level are the product-specific market data, e.g. `SpecificFXForwardMarketData <: AbstractProductSpecificMarketData`. This contains the market data for a specific product (here currency pairs) for the whole time series. 
The function `get_specific_market_data(product, container)` takes a container (level 1) and returns a product-specific market data item. It is rather slow and should not be called too often.

3. The lowest level are the specific curves. They are stored as OrderedDicts, with the valuation_dates as keys, in the product-specific market data structures. Example: `market_data.fx_forward_curves[valuation_date]`.

The idea of this data model is that it should be fast to price a whole time series of a product, either for studying price evolution / backtesting P&Ls (using real market data time series) or for market risk scenario P&Ls (using and artificial time series).

=#


## Market Data time series

abstract type AbstractTimeSeries end
Base.Broadcast.broadcastable(q:: AbstractTimeSeries) = Ref(q) # treat it as a scalar in broadcasting

Base.getindex(ts:: AbstractTimeSeries, valuation_date:: Date) = ts.curves[valuation_date]
Base.length(ts:: AbstractTimeSeries) = length(ts.curves)
Base.keys(ts:: AbstractTimeSeries) = keys(ts.curves)

struct FXForwardTimeSeries{BaseCurrency <: Currency, QuoteCurrency <: Currency, C <: Curve} <: AbstractTimeSeries
    curves:: SortedDict{Date, C}
end

FXForwardTimeSeries(::BaseCurrency, ::QuoteCurrency, dates:: AbstractVector{Date}, curves:: AbstractVector{C}) where {BaseCurrency, QuoteCurrency, C} =
    FXForwardTimeSeries{BaseCurrency, QuoteCurrency, C}(SortedDict(dates .=> curves))

struct DiscountTimeSeries{BaseCurrency <: Currency, C <: Curve} <: AbstractTimeSeries
    curves:: SortedDict{Date, C}
end

DiscountTimeSeries(::BaseCurrency, dates:: AbstractVector{Date}, curves:: AbstractVector{C}) where {BaseCurrency, C} = 
    DiscountTimeSeries{BaseCurrency, C}(SortedDict(dates .=> curves))

## Market data definitions per product


# The product specific market data contains only market data required for valuation of the products.
# No dynamic market data selection (e.g. for currencies, rate indices, etc.) required anymore.

abstract type AbstractProductSpecificMarketData end
Base.Broadcast.broadcastable(q:: AbstractProductSpecificMarketData) = Ref(q) # treat it as a scalar in broadcasting

"""
Container for the market data required to price FX Forwards for a specific currency pair.
The currency pair information is encoded in the type signature so that it is available at compile time.
"""
struct SpecificFXForwardMarketData{BaseCurrency <: Currency, QuoteCurrency <: Currency, C1 <: FXForwardTimeSeries, C2 <: DiscountTimeSeries} <: AbstractProductSpecificMarketData
    fx_forward_curves:: C1
    discount_curves:: C2
    flip_fx_direction:: Bool
end

SpecificFXForwardMarketData(::BaseCurrency, ::QuoteCurrency, fx_forward_curve:: C1, base_ccy_discount_curve:: C2; flip_fx_direction=false) where {BaseCurrency, QuoteCurrency, C1, C2} = 
    SpecificFXForwardMarketData{BaseCurrency, QuoteCurrency, C1, C2}(fx_forward_curve, base_ccy_discount_curve, flip_fx_direction)


## Market data container for a whole product class (e.g. FX Forwards)

abstract type AbstractMarketDataContainer end
Base.Broadcast.broadcastable(q:: AbstractMarketDataContainer) = Ref(q) # treat it as a scalar in broadcasting

"""
Check if the time series are consistent for all market data
"""
function _check_scenario_consistency(x:: X) where {X <: AbstractMarketDataContainer}
    ref_length = -1
    local ref_dates
    for field in fieldnames(X)
        md_dict = getproperty(x, field)
        for md_series in values(md_dict)
        
            if ref_length == -1
                ref_length = length(md_series)
                ref_length > 0 || error("time series is empty")
                ref_dates = collect(keys(md_series))
            else
                length(md_series) == ref_length || error("inconsistent time series lengths")
                ref_dates == collect(keys(md_series)) || error("inconsistent scenario dates")
            end
        end
    end
end

struct FXForwardMarketDataContainer <: AbstractMarketDataContainer
    fx_forward_curves:: Dict{Tuple{Currency, Currency}, FXForwardTimeSeries}
    discount_curves:: Dict{Currency, DiscountTimeSeries}

    function FXForwardMarketDataContainer(fx_forward_curves, discount_curves)
        container = new(fx_forward_curves, discount_curves)
        _check_scenario_consistency(container)
        return container
    end
end

function FXForwardMarketDataContainer(fx_forward_curves:: AbstractVector{<: FXForwardTimeSeries}, discount_curves:: AbstractVector{<: DiscountTimeSeries})
    fx_forward_curve_dict = Dict{Tuple{Currency, Currency}, FXForwardTimeSeries}()
    for curve in fx_forward_curves
        base_currency = typeof(curve).parameters[1]()
        quote_currency = typeof(curve).parameters[2]()
        fx_forward_curve_dict[(base_currency, quote_currency)] = curve
    end

    discount_curve_dict = Dict{Currency, DiscountTimeSeries}()
    for curve in discount_curves
        base_currency = typeof(curve).parameters[1]()
        discount_curve_dict[base_currency] = curve
    end
    return FXForwardMarketDataContainer(fx_forward_curve_dict, discount_curve_dict)
end

get_spot_rates(market_data_container:: FXForwardMarketDataContainer) = Dict(k => interpolate(t"2D", last(v.curves).second) for  (k, v) in pairs(market_data_container.fx_forward_curves))
get_spot_rates(market_data_container:: FXForwardMarketDataContainer, valuation_date:: Date) = Dict(k => interpolate(t"2D", v.curves[valuation_date]) for  (k, v) in pairs(market_data_container.fx_forward_curves))

get_dates(market_data_container:: FXForwardMarketDataContainer) = collect(keys(first(market_data_container.fx_forward_curves).second.curves))

"""
Returns the market data items required for valuation of a specific product
"""
function get_specific_market_data(product:: FXForward, container:: FXForwardMarketDataContainer)
    quote_currency = product.quote_currency
    base_currency = typeof(product.notional_base_currency).parameters[2]()

    discount_curve_time_series = container.discount_curves[quote_currency]
    if (base_currency, quote_currency) ∈ keys(container.fx_forward_curves)
        fx_time_series = container.fx_forward_curves[(base_currency, quote_currency)]
        flip_fx_direction = false
    elseif (quote_currency, base_currency) ∈ keys(container.fx_forward_curves)
        fx_time_series = container.fx_forward_curves[(quote_currency, base_currency)]
        flip_fx_direction = true
    else
        error("currency pair $((quote_currency, base_currency)) not found")
    end

    return SpecificFXForwardMarketData(base_currency, quote_currency, fx_time_series, discount_curve_time_series; flip_fx_direction=flip_fx_direction)
end
