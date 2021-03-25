## Product definitions

"""
Base type for all product definitions
"""
abstract type AbstractProduct end

Base.Broadcast.broadcastable(q:: AbstractProduct) = Ref(q) # treat it as a scalar in broadcasting

"""
Definition of an FX Forward product
"""
struct FXForward{T <: Real, BaseCurrency <: Currency, QuoteCurrency <: Currency} <: AbstractProduct
    notional_base_currency:: CurrencyAmount{T, BaseCurrency}
    quote_currency:: QuoteCurrency
    forward_fx_rate:: ExchangeRate{T, BaseCurrency, QuoteCurrency}
    tenor:: Tenor # relative time to maturity
end
