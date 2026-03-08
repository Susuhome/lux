defmodule Lux.Integrations.Binance.WebSocket do
  @moduledoc """
  WebSocket client for Binance real-time market data streams.

  Supports combined streams for multiple symbols and stream types:
  - `<symbol>@trade` — Individual trade updates
  - `<symbol>@kline_<interval>` — Kline/candlestick updates
  - `<symbol>@depth<levels>` — Order book depth
  - `<symbol>@ticker` — 24hr ticker stats
  - `<symbol>@miniTicker` — Mini ticker
  - `<symbol>@bookTicker` — Best bid/ask

  ## Usage

      {:ok, pid} = Lux.Integrations.Binance.WebSocket.start_link(%{
        streams: ["btcusdt@trade", "ethusdt@ticker"],
        handler: self()
      })

  Messages arrive as `{:binance_ws, stream_name, data}`.
  """

  use GenServer
  require Logger

  @ws_base "wss://stream.binance.com:9443/stream"
  @futures_ws_base "wss://fstream.binance.com/stream"

  defmodule State do
    @moduledoc false
    defstruct [:conn, :ws, :handler, :streams, :futures, :connected]
  end

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  def subscribe(pid, streams), do: GenServer.cast(pid, {:subscribe, streams})
  def unsubscribe(pid, streams), do: GenServer.cast(pid, {:unsubscribe, streams})

  @impl true
  def init(opts) do
    state = %State{
      handler: opts[:handler] || self(),
      streams: opts[:streams] || [],
      futures: opts[:futures] || false,
      connected: false
    }
    send(self(), :connect)
    {:ok, state}
  end

  @impl true
  def handle_info(:connect, state) do
    base = if state.futures, do: @futures_ws_base, else: @ws_base
    uri = URI.parse(base)
    host = String.to_charlist(uri.host)

    case :gun.open(host, uri.port || 443, %{protocols: [:http], transport: :tls, tls_opts: [verify: :verify_none]}) do
      {:ok, conn} -> {:noreply, %{state | conn: conn}}
      {:error, reason} ->
        Logger.error("Binance WS connect failed: #{inspect(reason)}")
        Process.send_after(self(), :connect, 5_000)
        {:noreply, state}
    end
  end

  def handle_info({:gun_up, conn, :http}, %{conn: conn} = state) do
    params = if state.streams != [], do: "?streams=#{Enum.join(state.streams, "/")}", else: ""
    ws = :gun.ws_upgrade(conn, String.to_charlist(params))
    {:noreply, %{state | ws: ws}}
  end

  def handle_info({:gun_upgrade, _conn, _ref, [<<"websocket">>], _}, state) do
    Logger.info("Binance WS connected")
    {:noreply, %{state | connected: true}}
  end

  def handle_info({:gun_ws, _conn, _ref, {:text, data}}, state) do
    case Jason.decode(data) do
      {:ok, %{"stream" => stream, "data" => payload}} ->
        send(state.handler, {:binance_ws, stream, payload})
      {:ok, msg} ->
        send(state.handler, {:binance_ws, "unknown", msg})
      _ -> :ok
    end
    {:noreply, state}
  end

  def handle_info({:gun_ws, _conn, _ref, :close}, state) do
    Logger.warning("Binance WS closed, reconnecting...")
    Process.send_after(self(), :connect, 1_000)
    {:noreply, %{state | connected: false}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_cast({:subscribe, streams}, state) do
    new_streams = Enum.uniq(state.streams ++ streams)
    if state.connected, do: send_sub(state.conn, state.ws, "SUBSCRIBE", streams)
    {:noreply, %{state | streams: new_streams}}
  end

  def handle_cast({:unsubscribe, streams}, state) do
    new_streams = state.streams -- streams
    if state.connected, do: send_sub(state.conn, state.ws, "UNSUBSCRIBE", streams)
    {:noreply, %{state | streams: new_streams}}
  end

  defp send_sub(conn, ws, method, streams) do
    msg = Jason.encode!(%{method: method, params: streams, id: System.unique_integer([:positive])})
    :gun.ws_send(conn, ws, {:text, msg})
  end
end
