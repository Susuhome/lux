defmodule Lux.Integrations.Coinbase.WebSocket do
  @moduledoc """
  WebSocket client for Coinbase Advanced Trade real-time market data feeds.

  Supports the following channels:
  - `ticker` — Real-time price updates
  - `ticker_batch` — Batched price updates (every 5 seconds)
  - `level2` — Order book updates
  - `market_trades` — Trade execution feed
  - `status` — Product status changes
  - `candles` — Real-time candle updates
  - `heartbeats` — Connection health monitoring

  ## Usage

      {:ok, pid} = Lux.Integrations.Coinbase.WebSocket.start_link(%{
        product_ids: ["BTC-USD", "ETH-USD"],
        channels: ["ticker", "heartbeats"],
        api_key: "your-key",
        api_secret: "your-secret",
        handler: self()
      })

  Messages are sent to the handler process as:

      {:coinbase_ws, channel, data}

  ## Authentication

  WebSocket connections require HMAC-SHA256 authentication using
  the same API key and secret as the REST API.
  """

  use GenServer
  require Logger

  @ws_endpoint "wss://advanced-trade-ws.coinbase.com"
  @heartbeat_interval 30_000

  @valid_channels ~w(ticker ticker_batch level2 market_trades status candles heartbeats)

  defmodule State do
    @moduledoc false
    defstruct [
      :conn,
      :ws,
      :handler,
      :api_key,
      :api_secret,
      :product_ids,
      :channels,
      :connected,
      :subscribed
    ]
  end

  # Client API

  @doc """
  Starts a WebSocket connection to Coinbase Advanced Trade.

  ## Options

    * `:product_ids` - List of product IDs to subscribe to (required)
    * `:channels` - List of channels to subscribe to (default: `["ticker", "heartbeats"]`)
    * `:api_key` - Coinbase API key (required)
    * `:api_secret` - Coinbase API secret (required)
    * `:handler` - PID to receive messages (default: caller)
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc "Subscribe to additional channels or products."
  def subscribe(pid, product_ids, channels) do
    GenServer.cast(pid, {:subscribe, product_ids, channels})
  end

  @doc "Unsubscribe from channels or products."
  def unsubscribe(pid, product_ids, channels) do
    GenServer.cast(pid, {:unsubscribe, product_ids, channels})
  end

  @doc "Returns valid channel names."
  def valid_channels, do: @valid_channels

  # Server callbacks

  @impl true
  def init(opts) do
    state = %State{
      handler: opts[:handler] || self(),
      api_key: opts[:api_key] || Lux.Integrations.Coinbase.coinbase_api_key(),
      api_secret: opts[:api_secret] || Lux.Integrations.Coinbase.coinbase_api_secret(),
      product_ids: opts[:product_ids] || [],
      channels: opts[:channels] || ["ticker", "heartbeats"],
      connected: false,
      subscribed: false
    }

    send(self(), :connect)
    {:ok, state}
  end

  @impl true
  def handle_info(:connect, state) do
    Logger.info("Coinbase WS: connecting to #{@ws_endpoint}")

    case :gun.open(~c"advanced-trade-ws.coinbase.com", 443, %{
           protocols: [:http],
           transport: :tls,
           tls_opts: [verify: :verify_none]
         }) do
      {:ok, conn} ->
        {:noreply, %{state | conn: conn}}

      {:error, reason} ->
        Logger.error("Coinbase WS: connection failed: #{inspect(reason)}")
        Process.send_after(self(), :connect, 5_000)
        {:noreply, state}
    end
  end

  def handle_info({:gun_up, conn, :http}, %{conn: conn} = state) do
    ws = :gun.ws_upgrade(conn, ~c"/")
    {:noreply, %{state | ws: ws}}
  end

  def handle_info({:gun_upgrade, conn, _ref, [<<"websocket">>], _headers}, %{conn: conn} = state) do
    Logger.info("Coinbase WS: connected, subscribing...")
    state = %{state | connected: true}
    send_subscribe(state)
    schedule_heartbeat()
    {:noreply, %{state | subscribed: true}}
  end

  def handle_info({:gun_ws, _conn, _ref, {:text, data}}, state) do
    case Jason.decode(data) do
      {:ok, %{"channel" => channel} = msg} ->
        send(state.handler, {:coinbase_ws, channel, msg})

      {:ok, msg} ->
        send(state.handler, {:coinbase_ws, "unknown", msg})

      {:error, _} ->
        Logger.warning("Coinbase WS: failed to decode message")
    end

    {:noreply, state}
  end

  def handle_info({:gun_ws, _conn, _ref, :close}, state) do
    Logger.warning("Coinbase WS: connection closed, reconnecting...")
    Process.send_after(self(), :connect, 1_000)
    {:noreply, %{state | connected: false, subscribed: false}}
  end

  def handle_info({:gun_down, _conn, :ws, _reason, _}, state) do
    Logger.warning("Coinbase WS: connection down, reconnecting...")
    Process.send_after(self(), :connect, 1_000)
    {:noreply, %{state | connected: false, subscribed: false}}
  end

  def handle_info(:heartbeat_check, state) do
    if state.connected do
      schedule_heartbeat()
    end

    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def handle_cast({:subscribe, product_ids, channels}, state) do
    new_state = %{
      state
      | product_ids: Enum.uniq(state.product_ids ++ product_ids),
        channels: Enum.uniq(state.channels ++ channels)
    }

    if state.connected do
      send_subscription_message(state.conn, "subscribe", product_ids, channels, state)
    end

    {:noreply, new_state}
  end

  def handle_cast({:unsubscribe, product_ids, channels}, state) do
    new_state = %{
      state
      | product_ids: state.product_ids -- product_ids,
        channels: state.channels -- channels
    }

    if state.connected do
      send_subscription_message(state.conn, "unsubscribe", product_ids, channels, state)
    end

    {:noreply, new_state}
  end

  # Private helpers

  defp send_subscribe(state) do
    send_subscription_message(state.conn, "subscribe", state.product_ids, state.channels, state)
  end

  defp send_subscription_message(conn, type, product_ids, channels, state) do
    timestamp = Integer.to_string(System.system_time(:second))
    products_str = Enum.join(product_ids, ",")
    message = timestamp <> channels_str(channels) <> products_str

    signature = Lux.Integrations.Coinbase.sign(message, state.api_secret)

    payload =
      Jason.encode!(%{
        type: type,
        product_ids: product_ids,
        channel: hd(channels),
        api_key: state.api_key,
        timestamp: timestamp,
        signature: signature
      })

    :gun.ws_send(conn, state.ws, {:text, payload})
  end

  defp channels_str(channels), do: Enum.join(channels, ",")

  defp schedule_heartbeat do
    Process.send_after(self(), :heartbeat_check, @heartbeat_interval)
  end
end
