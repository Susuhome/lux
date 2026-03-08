defmodule Lux.Prisms.Web3.Hyperliquid.TradingEngineTest do
  use ExUnit.Case, async: true
  alias Lux.Prisms.Web3.Hyperliquid.TradingEngine

  setup do
    name = :"hl_#{:rand.uniform(1_000_000)}"
    {:ok, pid} = TradingEngine.start_link(name: name, max_leverage: 50)
    %{pid: pid}
  end

  test "place order", %{pid: pid} do
    {:ok, order} = TradingEngine.place_order(pid, %{symbol: "BTC-PERP", side: :long, price: 65000, size: 1, leverage: 10})
    assert order.symbol == "BTC-PERP"
    assert order.status == :open
  end

  test "reject excessive leverage", %{pid: pid} do
    assert {:error, :leverage_exceeded} = TradingEngine.place_order(pid, %{symbol: "BTC", side: :long, leverage: 100})
  end

  test "cancel order", %{pid: pid} do
    {:ok, order} = TradingEngine.place_order(pid, %{symbol: "ETH", side: :short, price: 3000, size: 5})
    {:ok, cancelled} = TradingEngine.cancel_order(pid, order.id)
    assert cancelled.status == :cancelled
  end

  test "list open orders", %{pid: pid} do
    {:ok, _} = TradingEngine.place_order(pid, %{symbol: "BTC", side: :long})
    {:ok, o2} = TradingEngine.place_order(pid, %{symbol: "ETH", side: :short})
    TradingEngine.cancel_order(pid, o2.id)
    {:ok, open} = TradingEngine.list_orders(pid)
    assert length(open) == 1
  end

  test "set leverage", %{pid: pid} do
    {:ok, pos} = TradingEngine.set_leverage(pid, "BTC-PERP", 20)
    assert pos.leverage == 20
  end

  test "set leverage exceeds max", %{pid: pid} do
    assert {:error, :leverage_exceeded} = TradingEngine.set_leverage(pid, "BTC", 100)
  end

  test "close position", %{pid: pid} do
    TradingEngine.set_leverage(pid, "BTC", 10)
    {:ok, result} = TradingEngine.close_position(pid, "BTC")
    assert result.pnl
  end

  test "close nonexistent position", %{pid: pid} do
    assert {:error, :no_position} = TradingEngine.close_position(pid, "DOGE")
  end

  test "risk check", %{pid: pid} do
    TradingEngine.set_leverage(pid, "BTC", 5)
    {:ok, risk} = TradingEngine.risk_check(pid)
    assert risk.risk_level == :low
    assert risk.total_positions == 1
  end

  test "pnl summary empty", %{pid: pid} do
    {:ok, pnl} = TradingEngine.pnl_summary(pid)
    assert pnl.total_pnl == 0
    assert pnl.trades == 0
  end

  test "list positions", %{pid: pid} do
    TradingEngine.set_leverage(pid, "BTC", 10)
    TradingEngine.set_leverage(pid, "ETH", 5)
    {:ok, positions} = TradingEngine.list_positions(pid)
    assert length(positions) == 2
  end
end
