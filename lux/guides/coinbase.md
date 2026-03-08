# Coinbase Exchange Integration

This guide covers the Coinbase Advanced Trade API integration for Lux.

## Overview

- **Market Data** — Products, ticker, orderbook, candles
- **Historical Data** — OHLCV candles with configurable granularity
- **Account Management** — Account balances, portfolio tracking
- **Order Management** — Create/cancel orders (market, limit, stop-limit)
- **WebSocket Feeds** — Real-time ticker, trades, order book, candles
- **Rate Limiting** — Built-in 429 handling with retry

## Configuration

```elixir
config :lux, :api_keys,
  coinbase_api_key: "your-api-key",
  coinbase_api_secret: "your-api-secret"
```

## Authentication

Uses API Key + HMAC-SHA256 signing with headers:
- `CB-ACCESS-KEY` — API key
- `CB-ACCESS-SIGN` — HMAC-SHA256(timestamp + method + path + body)
- `CB-ACCESS-TIMESTAMP` — Unix timestamp

## Usage

### Market Data

```elixir
alias Lux.Lenses.Coinbase.MarketData

{:ok, products} = MarketData.get_products()
{:ok, ticker} = MarketData.get_ticker("BTC-USD")
{:ok, book} = MarketData.get_orderbook("BTC-USD")
```

### Historical Data (Candles)

```elixir
alias Lux.Lenses.Coinbase.MarketHistory

# Get hourly candles (default)
{:ok, candles} = MarketHistory.get_candles("BTC-USD")

# With time range and granularity
{:ok, candles} = MarketHistory.get_candles("BTC-USD", %{
  start: "1704067200",
  end: "1704153600",
  granularity: "FIVE_MINUTE"
})

# Each candle: %{start, open, high, low, close, volume}

# Valid granularities
MarketHistory.valid_granularities()
# => ["ONE_MINUTE", "FIVE_MINUTE", "FIFTEEN_MINUTE", "THIRTY_MINUTE",
#     "ONE_HOUR", "TWO_HOUR", "SIX_HOUR", "ONE_DAY"]
```

### Accounts

```elixir
alias Lux.Lenses.Coinbase.Accounts

{:ok, accounts} = Accounts.list_accounts()
{:ok, account} = Accounts.get_account("account-uuid")
{:ok, portfolios} = Accounts.list_portfolios()
{:ok, portfolio} = Accounts.get_portfolio("portfolio-uuid")
```

### Orders

```elixir
alias Lux.Prisms.Coinbase.CreateOrder
alias Lux.Prisms.Coinbase.CancelOrder

# Market buy
{:ok, order} = CreateOrder.handler(%{
  product_id: "BTC-USD",
  side: "BUY",
  order_type: "market",
  amount: "100.00"
}, %{name: "MyAgent"})

# Limit sell
{:ok, order} = CreateOrder.handler(%{
  product_id: "ETH-USD",
  side: "SELL",
  order_type: "limit",
  base_size: "1.0",
  limit_price: "3000.00"
}, %{name: "MyAgent"})

# Cancel
{:ok, result} = CancelOrder.handler(%{order_ids: ["order-1"]}, %{name: "MyAgent"})
```

### WebSocket Feeds

```elixir
alias Lux.Integrations.Coinbase.WebSocket

# Start WebSocket connection
{:ok, ws} = WebSocket.start_link(%{
  product_ids: ["BTC-USD", "ETH-USD"],
  channels: ["ticker", "heartbeats"],
  api_key: "your-key",
  api_secret: "your-secret",
  handler: self()
})

# Receive messages
receive do
  {:coinbase_ws, "ticker", data} ->
    IO.inspect(data, label: "Ticker update")
end

# Subscribe to more channels
WebSocket.subscribe(ws, ["SOL-USD"], ["market_trades"])

# Unsubscribe
WebSocket.unsubscribe(ws, ["SOL-USD"], ["market_trades"])

# Available channels
WebSocket.valid_channels()
# => ["ticker", "ticker_batch", "level2", "market_trades",
#     "status", "candles", "heartbeats"]
```

## Modules

| Module | Type | Description |
|--------|------|-------------|
| `Lux.Integrations.Coinbase` | Auth | HMAC-SHA256 signing helpers |
| `Lux.Integrations.Coinbase.Client` | Client | HTTP client with auth |
| `Lux.Integrations.Coinbase.WebSocket` | Client | Real-time WebSocket feeds |
| `Lux.Lenses.Coinbase.MarketData` | Lens | Products, ticker, orderbook |
| `Lux.Lenses.Coinbase.MarketHistory` | Lens | Historical candles/OHLCV |
| `Lux.Lenses.Coinbase.Accounts` | Lens | Account balances, portfolios |
| `Lux.Prisms.Coinbase.CreateOrder` | Prism | Place orders |
| `Lux.Prisms.Coinbase.CancelOrder` | Prism | Cancel orders |

## Error Handling

```elixir
case Client.request(:get, "/products", opts) do
  {:ok, data} -> handle_data(data)
  {:error, :invalid_credentials} -> # Bad API key/secret (401)
  {:error, :rate_limited} -> # Too many requests (429)
  {:error, {status, message}} -> # Other API error
end
```

## API Reference

- Base URL: `https://api.coinbase.com/api/v3/brokerage`
- WebSocket: `wss://advanced-trade-ws.coinbase.com`
- Rate limits: 10 req/sec per endpoint
- [Coinbase Advanced Trade docs](https://docs.cdp.coinbase.com/advanced-trade/docs/rest-api-overview)
- [WebSocket docs](https://docs.cdp.coinbase.com/advanced-trade/docs/ws-overview)
