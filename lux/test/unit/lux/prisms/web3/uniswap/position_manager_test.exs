defmodule Lux.Prisms.Web3.Uniswap.PositionManagerTest do
  use ExUnit.Case, async: true
  alias Lux.Prisms.Web3.Uniswap.PositionManager

  setup do
    name = :"uni_#{:rand.uniform(1_000_000)}"
    {:ok, pid} = PositionManager.start_link(name: name)
    %{pid: pid}
  end

  test "create position", %{pid: pid} do
    {:ok, pos} = PositionManager.create_position(pid, %{
      token0: "WETH", token1: "USDC", fee_tier: 3000,
      price_lower: 1800.0, price_upper: 2200.0, amount0: 1.0, amount1: 2000.0
    })
    assert pos.pool.token0 == "WETH"
    assert pos.status == :active
  end

  test "close position", %{pid: pid} do
    {:ok, pos} = PositionManager.create_position(pid, %{token0: "A", token1: "B", price_lower: 1.0, price_upper: 2.0})
    {:ok, closed} = PositionManager.close_position(pid, pos.id)
    assert closed.status == :closed
  end

  test "get position", %{pid: pid} do
    {:ok, pos} = PositionManager.create_position(pid, %{token0: "A", token1: "B", price_lower: 1.0, price_upper: 2.0})
    {:ok, found} = PositionManager.get_position(pid, pos.id)
    assert found.id == pos.id
  end

  test "not found", %{pid: pid} do
    assert {:error, :not_found} = PositionManager.get_position(pid, "nope")
  end

  test "list positions", %{pid: pid} do
    {:ok, _} = PositionManager.create_position(pid, %{token0: "A", token1: "B", price_lower: 1.0, price_upper: 2.0})
    {:ok, _} = PositionManager.create_position(pid, %{token0: "C", token1: "D", price_lower: 3.0, price_upper: 4.0})
    {:ok, list} = PositionManager.list_positions(pid)
    assert length(list) == 2
  end

  test "collect fees", %{pid: pid} do
    {:ok, pos} = PositionManager.create_position(pid, %{token0: "A", token1: "B", price_lower: 1.0, price_upper: 2.0})
    {:ok, result} = PositionManager.collect_fees(pid, pos.id)
    assert result.collected.token0 == 0
  end

  test "rebalance", %{pid: pid} do
    {:ok, pos} = PositionManager.create_position(pid, %{token0: "A", token1: "B", price_lower: 1.0, price_upper: 2.0})
    {:ok, updated} = PositionManager.rebalance(pid, pos.id, %{price_lower: 1.5, price_upper: 2.5})
    assert updated.price_lower == 1.5
    assert updated.price_upper == 2.5
  end

  test "health check in range", %{pid: pid} do
    {:ok, pos} = PositionManager.create_position(pid, %{token0: "A", token1: "B", price_lower: 1800.0, price_upper: 2200.0})
    {:ok, health} = PositionManager.health_check(pid, pos.id)
    assert health.in_range
    refute health.needs_rebalance
  end

  test "portfolio summary", %{pid: pid} do
    {:ok, _} = PositionManager.create_position(pid, %{token0: "A", token1: "B", price_lower: 1.0, price_upper: 2.0})
    {:ok, _} = PositionManager.create_position(pid, %{token0: "C", token1: "D", price_lower: 3.0, price_upper: 4.0})
    {:ok, summary} = PositionManager.portfolio_summary(pid)
    assert summary.total_positions == 2
    assert summary.active == 2
  end

  test "fee tiers validation", %{pid: pid} do
    {:ok, pos} = PositionManager.create_position(pid, %{token0: "A", token1: "B", fee_tier: 500, price_lower: 1.0, price_upper: 2.0})
    assert pos.pool.fee_tier == 500
  end
end
