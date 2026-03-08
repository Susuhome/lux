defmodule Lux.Prisms.Web3.PancakeSwap.FarmManagerTest do
  use ExUnit.Case, async: true
  alias Lux.Prisms.Web3.PancakeSwap.FarmManager

  setup do
    name = :"pcs_#{:rand.uniform(1_000_000)}"
    {:ok, pid} = FarmManager.start_link(name: name)
    %{pid: pid}
  end

  test "add farm", %{pid: pid} do
    {:ok, farm} = FarmManager.add_farm(pid, %{pair: "CAKE-BNB", lp_amount: 100.0, apr: 45.0})
    assert farm.pair == "CAKE-BNB"
    assert farm.status == :active
  end

  test "remove farm", %{pid: pid} do
    {:ok, farm} = FarmManager.add_farm(pid, %{pair: "CAKE-BNB"})
    {:ok, removed} = FarmManager.remove_farm(pid, farm.id)
    assert removed.status == :withdrawn
  end

  test "stake cake", %{pid: pid} do
    {:ok, s} = FarmManager.stake_cake(pid, 1000)
    assert s.staked == 1000
    {:ok, s2} = FarmManager.stake_cake(pid, 500)
    assert s2.staked == 1500
  end

  test "unstake cake", %{pid: pid} do
    FarmManager.stake_cake(pid, 1000)
    {:ok, result} = FarmManager.unstake_cake(pid, 600)
    assert result.unstaked == 600
    assert result.remaining == 400
  end

  test "harvest", %{pid: pid} do
    {:ok, farm} = FarmManager.add_farm(pid, %{pair: "CAKE-BNB"})
    {:ok, result} = FarmManager.harvest(pid, farm.id)
    assert result.harvested == 0
  end

  test "list farms", %{pid: pid} do
    {:ok, _} = FarmManager.add_farm(pid, %{pair: "A-B"})
    {:ok, _} = FarmManager.add_farm(pid, %{pair: "C-D"})
    {:ok, farms} = FarmManager.list_farms(pid)
    assert length(farms) == 2
  end

  test "estimate swap" do
    {:ok, r} = FarmManager.estimate_swap(%{amount_in: 1000, price: 2.0, fee_rate: 0.0025})
    assert r.amount_out > 1980
    assert r.fee > 0
  end

  test "analyze farm" do
    {:ok, r} = FarmManager.analyze_farm(%{apr: 50, tvl: 50_000_000})
    assert r.risk == :low
    assert r.daily_yield > 0
  end

  test "not found farm", %{pid: pid} do
    assert {:error, :not_found} = FarmManager.remove_farm(pid, "nope")
  end
end
