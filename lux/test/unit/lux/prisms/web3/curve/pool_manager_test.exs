defmodule Lux.Prisms.Web3.Curve.PoolManagerTest do
  use ExUnit.Case, async: true
  alias Lux.Prisms.Web3.Curve.PoolManager

  setup do
    name = :"curve_#{:rand.uniform(1_000_000)}"
    {:ok, pid} = PoolManager.start_link(name: name)
    %{pid: pid}
  end

  test "add liquidity", %{pid: pid} do
    {:ok, pos} = PoolManager.add_liquidity(pid, %{pool: "3pool", tokens: ["DAI", "USDC", "USDT"], amounts: [1000, 1000, 1000], lp_amount: 3000.0})
    assert pos.pool == "3pool"
    assert pos.status == :active
  end

  test "remove liquidity partial", %{pid: pid} do
    {:ok, pos} = PoolManager.add_liquidity(pid, %{pool: "3pool", lp_amount: 1000.0})
    {:ok, result} = PoolManager.remove_liquidity(pid, pos.id, 50)
    assert result.removed_lp == 500.0
    assert result.remaining_lp == 500.0
  end

  test "remove liquidity full closes position", %{pid: pid} do
    {:ok, pos} = PoolManager.add_liquidity(pid, %{pool: "3pool", lp_amount: 1000.0})
    {:ok, result} = PoolManager.remove_liquidity(pid, pos.id, 100)
    assert result.position.status == :closed
  end

  test "stake gauge", %{pid: pid} do
    {:ok, pos} = PoolManager.add_liquidity(pid, %{pool: "3pool", lp_amount: 100.0})
    {:ok, staked} = PoolManager.stake_gauge(pid, pos.id)
    assert staked.staked
  end

  test "unstake gauge", %{pid: pid} do
    {:ok, pos} = PoolManager.add_liquidity(pid, %{pool: "3pool", lp_amount: 100.0})
    {:ok, _} = PoolManager.stake_gauge(pid, pos.id)
    {:ok, unstaked} = PoolManager.unstake_gauge(pid, pos.id)
    refute unstaked.staked
  end

  test "claim rewards", %{pid: pid} do
    {:ok, pos} = PoolManager.add_liquidity(pid, %{pool: "3pool", lp_amount: 100.0})
    {:ok, result} = PoolManager.claim_rewards(pid, pos.id)
    assert result.claimed.crv == 0
  end

  test "get and list positions", %{pid: pid} do
    {:ok, pos} = PoolManager.add_liquidity(pid, %{pool: "3pool", lp_amount: 100.0})
    {:ok, found} = PoolManager.get_position(pid, pos.id)
    assert found.id == pos.id
    {:ok, list} = PoolManager.list_positions(pid)
    assert length(list) == 1
  end

  test "not found", %{pid: pid} do
    assert {:error, :not_found} = PoolManager.get_position(pid, "nope")
  end

  test "analyze pool", _ctx do
    {:ok, analysis} = PoolManager.analyze_pool(%{tvl: 500_000_000, volume_24h: 50_000_000, fee_rate: 0.0004})
    assert analysis.apr_estimate > 0
    assert analysis.risk_score <= 20
  end

  test "analyze low tvl pool", _ctx do
    {:ok, analysis} = PoolManager.analyze_pool(%{tvl: 500_000, volume_24h: 10_000})
    assert analysis.risk_score >= 50
  end
end
