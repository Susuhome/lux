defmodule Lux.Prisms.Web3.SushiSwap.CrossChainManagerTest do
  use ExUnit.Case, async: true
  alias Lux.Prisms.Web3.SushiSwap.CrossChainManager

  setup do
    name = :"sushi_#{:rand.uniform(1_000_000)}"
    {:ok, pid} = CrossChainManager.start_link(name: name)
    %{pid: pid}
  end

  test "add liquidity", %{pid: pid} do
    {:ok, pool} = CrossChainManager.add_liquidity(pid, %{token0: "SUSHI", token1: "ETH", amount0: 1000, amount1: 0.5, chain: :ethereum})
    assert pool.status == :active
    assert pool.chain == :ethereum
  end

  test "remove liquidity", %{pid: pid} do
    {:ok, pool} = CrossChainManager.add_liquidity(pid, %{token0: "A", token1: "B"})
    {:ok, removed} = CrossChainManager.remove_liquidity(pid, pool.id)
    assert removed.status == :removed
  end

  test "initiate bridge", %{pid: pid} do
    {:ok, bridge} = CrossChainManager.initiate_bridge(pid, %{token: "USDC", amount: 1000, from_chain: :ethereum, to_chain: :arbitrum})
    assert bridge.status == :pending
    assert bridge.from_chain == :ethereum
  end

  test "bridge unsupported chain", %{pid: pid} do
    assert {:error, :unsupported_chain} = CrossChainManager.initiate_bridge(pid, %{from_chain: :solana, to_chain: :ethereum})
  end

  test "bridge status", %{pid: pid} do
    {:ok, bridge} = CrossChainManager.initiate_bridge(pid, %{token: "ETH", amount: 1, from_chain: :ethereum, to_chain: :polygon})
    {:ok, status} = CrossChainManager.get_bridge_status(pid, bridge.id)
    assert status.status == :pending
  end

  test "stake sushi", %{pid: pid} do
    {:ok, s} = CrossChainManager.stake_sushi(pid, 1000)
    assert s.sushi_staked == 1000
    assert s.xsushi > 0
  end

  test "list pools", %{pid: pid} do
    {:ok, _} = CrossChainManager.add_liquidity(pid, %{token0: "A", token1: "B"})
    {:ok, pools} = CrossChainManager.list_pools(pid)
    assert length(pools) == 1
  end

  test "supported chains" do
    chains = CrossChainManager.supported_chains()
    assert :ethereum in chains
    assert :arbitrum in chains
  end

  test "estimate bridge fee" do
    {:ok, est} = CrossChainManager.estimate_bridge_fee(%{amount: 1000, from_chain: :ethereum, to_chain: :arbitrum})
    assert est.fee > 0
    assert est.estimated_time_minutes == 10
  end

  test "not found", %{pid: pid} do
    assert {:error, :not_found} = CrossChainManager.remove_liquidity(pid, "nope")
  end
end
