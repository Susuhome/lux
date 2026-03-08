defmodule Lux.Prisms.Web3.Gas.OptimizeTransactionTest do
  use ExUnit.Case, async: true

  alias Lux.Prisms.Web3.Gas.OptimizeTransaction
  alias Lux.Integrations.Web3.Gas.TransactionManager

  setup do
    {:ok, pid} = TransactionManager.start_link(name: nil)
    %{pid: pid}
  end

  test "submit via prism", %{pid: pid} do
    assert {:ok, result} = OptimizeTransaction.handler(
      %{action: "submit", tx: %{to: "0xabc", value: 100}, pid: pid}, []
    )
    assert result.status == :pending
  end

  test "speed_up via prism", %{pid: pid} do
    {:ok, %{id: id}} = TransactionManager.submit(pid, %{to: "0xabc", gas_price: 30})
    assert {:ok, result} = OptimizeTransaction.handler(
      %{action: "speed_up", tx_id: id, gas_multiplier: 2.0, pid: pid}, []
    )
    assert result.new_gas_price == 60
  end

  test "cancel via prism", %{pid: pid} do
    {:ok, %{id: id}} = TransactionManager.submit(pid, %{to: "0xabc"})
    assert {:ok, %{status: :cancelled}} = OptimizeTransaction.handler(
      %{action: "cancel", tx_id: id, pid: pid}, []
    )
  end

  test "batch via prism", %{pid: pid} do
    assert {:ok, result} = OptimizeTransaction.handler(
      %{action: "batch", transactions: [%{to: "0xa"}, %{to: "0xb"}], pid: pid}, []
    )
    assert result.count == 2
  end

  test "cost calculation via prism" do
    assert {:ok, result} = OptimizeTransaction.handler(
      %{action: "cost", gas_limit: 21_000, gas_price_gwei: 30.0, eth_price_usd: 2500.0}, []
    )
    assert result.cost_eth > 0
    assert result.cost_usd > 0
  end
end
