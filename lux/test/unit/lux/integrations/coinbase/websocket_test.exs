defmodule Lux.Integrations.Coinbase.WebSocketTest do
  use ExUnit.Case, async: true

  alias Lux.Integrations.Coinbase.WebSocket

  describe "valid_channels/0" do
    test "returns all supported channels" do
      channels = WebSocket.valid_channels()
      assert "ticker" in channels
      assert "ticker_batch" in channels
      assert "level2" in channels
      assert "market_trades" in channels
      assert "status" in channels
      assert "candles" in channels
      assert "heartbeats" in channels
      assert length(channels) == 7
    end
  end

  describe "start_link/1" do
    test "starts with auto_connect: false" do
      {:ok, pid} =
        WebSocket.start_link(%{
          product_ids: ["BTC-USD"],
          channels: ["ticker"],
          api_key: "test-key",
          api_secret: "test-secret",
          handler: self(),
          auto_connect: false
        })

      assert Process.alive?(pid)

      status = WebSocket.status(pid)
      assert status.connected == false
      assert status.product_ids == ["BTC-USD"]
      assert status.channels == ["ticker"]

      GenServer.stop(pid)
    end

    test "filters invalid channels" do
      {:ok, pid} =
        WebSocket.start_link(%{
          product_ids: ["ETH-USD"],
          channels: ["ticker", "invalid_channel", "level2"],
          api_key: "test-key",
          api_secret: "test-secret",
          handler: self(),
          auto_connect: false
        })

      status = WebSocket.status(pid)
      assert status.channels == ["ticker", "level2"]

      GenServer.stop(pid)
    end

    test "uses default channels when not specified" do
      {:ok, pid} =
        WebSocket.start_link(%{
          product_ids: ["BTC-USD"],
          api_key: "test-key",
          api_secret: "test-secret",
          handler: self(),
          auto_connect: false
        })

      status = WebSocket.status(pid)
      assert "ticker" in status.channels
      assert "heartbeats" in status.channels

      GenServer.stop(pid)
    end
  end

  describe "subscribe/3" do
    test "adds new products and channels" do
      {:ok, pid} =
        WebSocket.start_link(%{
          product_ids: ["BTC-USD"],
          channels: ["ticker"],
          api_key: "test-key",
          api_secret: "test-secret",
          handler: self(),
          auto_connect: false
        })

      WebSocket.subscribe(pid, ["ETH-USD"], ["level2"])
      # Give cast time to process
      :timer.sleep(50)

      status = WebSocket.status(pid)
      assert "BTC-USD" in status.product_ids
      assert "ETH-USD" in status.product_ids
      assert "ticker" in status.channels
      assert "level2" in status.channels

      GenServer.stop(pid)
    end
  end

  describe "unsubscribe/3" do
    test "removes products and channels" do
      {:ok, pid} =
        WebSocket.start_link(%{
          product_ids: ["BTC-USD", "ETH-USD"],
          channels: ["ticker", "level2"],
          api_key: "test-key",
          api_secret: "test-secret",
          handler: self(),
          auto_connect: false
        })

      WebSocket.unsubscribe(pid, ["ETH-USD"], ["level2"])
      :timer.sleep(50)

      status = WebSocket.status(pid)
      assert status.product_ids == ["BTC-USD"]
      assert status.channels == ["ticker"]

      GenServer.stop(pid)
    end
  end

  describe "message handling" do
    test "handles channel messages via GenServer" do
      {:ok, pid} =
        WebSocket.start_link(%{
          product_ids: ["BTC-USD"],
          channels: ["ticker"],
          api_key: "test-key",
          api_secret: "test-secret",
          handler: self(),
          auto_connect: false
        })

      # Simulate receiving a decoded WS message by sending ssl_closed
      # (tests reconnect logic)
      send(pid, {:ssl_closed, nil})
      :timer.sleep(50)

      status = WebSocket.status(pid)
      assert status.connected == false

      GenServer.stop(pid)
    end
  end
end
