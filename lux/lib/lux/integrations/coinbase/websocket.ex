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
  import Bitwise
  require Logger

  @ws_host "advanced-trade-ws.coinbase.com"
  @ws_port 443
  @ws_path "/"
  @heartbeat_interval 30_000
  @reconnect_delay 5_000

  @valid_channels ~w(ticker ticker_batch level2 market_trades status candles heartbeats)

  defmodule State do
    @moduledoc false
    defstruct [
      :socket,
      :handler,
      :api_key,
      :api_secret,
      :product_ids,
      :channels,
      :buffer,
      connected: false,
      subscribed: false,
      transport: :ssl
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
    * `:transport` - Transport module, `:ssl` (default) or a test mock
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

  @doc "Get current connection state."
  def status(pid) do
    GenServer.call(pid, :status)
  end

  # Server callbacks

  @impl true
  def init(opts) do
    state = %State{
      handler: opts[:handler] || self(),
      api_key: opts[:api_key] || Lux.Integrations.Coinbase.coinbase_api_key(),
      api_secret: opts[:api_secret] || Lux.Integrations.Coinbase.coinbase_api_secret(),
      product_ids: opts[:product_ids] || [],
      channels: validate_channels(opts[:channels] || ["ticker", "heartbeats"]),
      transport: opts[:transport] || :ssl,
      buffer: ""
    }

    if opts[:auto_connect] != false do
      send(self(), :connect)
    end

    {:ok, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply,
     %{
       connected: state.connected,
       subscribed: state.subscribed,
       product_ids: state.product_ids,
       channels: state.channels
     }, state}
  end

  @impl true
  def handle_info(:connect, state) do
    Logger.info("Coinbase WS: connecting to #{@ws_host}:#{@ws_port}")

    ssl_opts = [
      verify: :verify_none,
      active: true,
      packet: :raw,
      binary: true
    ]

    case :ssl.connect(~c"#{@ws_host}", @ws_port, ssl_opts, 10_000) do
      {:ok, socket} ->
        # Send WebSocket upgrade handshake
        key = Base.encode64(:crypto.strong_rand_bytes(16))

        handshake =
          "GET #{@ws_path} HTTP/1.1\r\n" <>
            "Host: #{@ws_host}\r\n" <>
            "Upgrade: websocket\r\n" <>
            "Connection: Upgrade\r\n" <>
            "Sec-WebSocket-Key: #{key}\r\n" <>
            "Sec-WebSocket-Version: 13\r\n" <>
            "\r\n"

        :ssl.send(socket, handshake)
        {:noreply, %{state | socket: socket}}

      {:error, reason} ->
        Logger.error("Coinbase WS: connection failed: #{inspect(reason)}")
        schedule_reconnect()
        {:noreply, state}
    end
  end

  def handle_info({:ssl, socket, data}, %{socket: socket, connected: false} = state) do
    buffer = state.buffer <> data

    if String.contains?(buffer, "\r\n\r\n") do
      if String.contains?(buffer, "101") do
        Logger.info("Coinbase WS: connected, subscribing...")
        state = %{state | connected: true, buffer: ""}
        send_subscribe(state)
        schedule_heartbeat()
        {:noreply, %{state | subscribed: true}}
      else
        Logger.error("Coinbase WS: handshake failed")
        :ssl.close(socket)
        schedule_reconnect()
        {:noreply, %{state | socket: nil, buffer: ""}}
      end
    else
      {:noreply, %{state | buffer: buffer}}
    end
  end

  def handle_info({:ssl, socket, data}, %{socket: socket, connected: true} = state) do
    case decode_ws_frame(data) do
      {:text, payload} ->
        handle_message(payload, state)

      {:close, _} ->
        Logger.warning("Coinbase WS: received close frame, reconnecting...")
        :ssl.close(socket)
        schedule_reconnect()
        {:noreply, %{state | connected: false, subscribed: false, socket: nil}}

      {:ping, _} ->
        send_ws_frame(socket, :pong, "")
        {:noreply, state}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:ssl_closed, _socket}, state) do
    Logger.warning("Coinbase WS: connection closed, reconnecting...")
    schedule_reconnect()
    {:noreply, %{state | connected: false, subscribed: false, socket: nil}}
  end

  def handle_info({:ssl_error, _socket, reason}, state) do
    Logger.error("Coinbase WS: SSL error: #{inspect(reason)}")
    schedule_reconnect()
    {:noreply, %{state | connected: false, subscribed: false, socket: nil}}
  end

  def handle_info(:heartbeat_check, state) do
    if state.connected, do: schedule_heartbeat()
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def handle_cast({:subscribe, product_ids, channels}, state) do
    valid = validate_channels(channels)

    new_state = %{
      state
      | product_ids: Enum.uniq(state.product_ids ++ product_ids),
        channels: Enum.uniq(state.channels ++ valid)
    }

    if state.connected do
      send_subscription_message(state.socket, "subscribe", product_ids, valid, state)
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
      send_subscription_message(state.socket, "unsubscribe", product_ids, channels, state)
    end

    {:noreply, new_state}
  end

  # Private helpers

  defp handle_message(payload, state) do
    case Jason.decode(payload) do
      {:ok, %{"channel" => channel} = msg} ->
        send(state.handler, {:coinbase_ws, channel, msg})

      {:ok, msg} ->
        send(state.handler, {:coinbase_ws, "unknown", msg})

      {:error, _} ->
        Logger.warning("Coinbase WS: failed to decode message")
    end

    {:noreply, state}
  end

  defp send_subscribe(state) do
    Enum.each(state.channels, fn channel ->
      send_subscription_message(state.socket, "subscribe", state.product_ids, [channel], state)
    end)
  end

  defp send_subscription_message(socket, type, product_ids, channels, state) do
    timestamp = Integer.to_string(System.system_time(:second))
    products_str = Enum.join(product_ids, ",")

    Enum.each(channels, fn channel ->
      message = timestamp <> channel <> products_str

      signature =
        :crypto.mac(:hmac, :sha256, state.api_secret || "", message)
        |> Base.encode16(case: :lower)

      payload =
        Jason.encode!(%{
          type: type,
          product_ids: product_ids,
          channel: channel,
          api_key: state.api_key,
          timestamp: timestamp,
          signature: signature
        })

      send_ws_frame(socket, :text, payload)
    end)
  end

  defp send_ws_frame(socket, :text, payload) do
    mask = :crypto.strong_rand_bytes(4)
    payload_bytes = :erlang.iolist_to_binary(payload)
    len = byte_size(payload_bytes)
    masked = mask_payload(payload_bytes, mask)

    frame =
      cond do
        len < 126 ->
          <<0x81, 0x80 ||| len, mask::binary-size(4), masked::binary>>

        len < 65536 ->
          <<0x81, 0x80 ||| 126, len::16, mask::binary-size(4), masked::binary>>

        true ->
          <<0x81, 0x80 ||| 127, len::64, mask::binary-size(4), masked::binary>>
      end

    :ssl.send(socket, frame)
  end

  defp send_ws_frame(socket, :pong, _payload) do
    :ssl.send(socket, <<0x8A, 0x80, 0, 0, 0, 0>>)
  end

  defp decode_ws_frame(<<_fin::1, _rsv::3, opcode::4, _mask::1, len::7, rest::binary>>)
       when len < 126 do
    <<payload::binary-size(len), _::binary>> = rest
    opcode_to_type(opcode, payload)
  end

  defp decode_ws_frame(<<_fin::1, _rsv::3, opcode::4, _mask::1, 126, len::16, rest::binary>>) do
    <<payload::binary-size(len), _::binary>> = rest
    opcode_to_type(opcode, payload)
  end

  defp decode_ws_frame(_), do: :unknown

  defp opcode_to_type(0x1, payload), do: {:text, payload}
  defp opcode_to_type(0x8, payload), do: {:close, payload}
  defp opcode_to_type(0x9, payload), do: {:ping, payload}
  defp opcode_to_type(0xA, payload), do: {:pong, payload}
  defp opcode_to_type(_, payload), do: {:unknown, payload}

  defp mask_payload(payload, <<m1, m2, m3, m4>>) do
    mask = [m1, m2, m3, m4]

    payload
    |> :erlang.binary_to_list()
    |> Enum.with_index()
    |> Enum.map(fn {byte, i} -> Bitwise.bxor(byte, Enum.at(mask, rem(i, 4))) end)
    |> :erlang.list_to_binary()
  end

  defp validate_channels(channels) do
    Enum.filter(channels, &(&1 in @valid_channels))
  end

  defp schedule_heartbeat do
    Process.send_after(self(), :heartbeat_check, @heartbeat_interval)
  end

  defp schedule_reconnect do
    Process.send_after(self(), :connect, @reconnect_delay)
  end
end
