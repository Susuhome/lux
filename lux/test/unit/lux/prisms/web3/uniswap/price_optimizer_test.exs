defmodule Lux.Prisms.Web3.Uniswap.PriceOptimizerTest do
  use ExUnit.Case, async: true
  alias Lux.Prisms.Web3.Uniswap.PriceOptimizer

  test "recommend fee tier for stable pair" do
    {:ok, r} = PriceOptimizer.recommend_fee_tier(%{correlation: 0.99})
    assert r.recommended_tier == 100
  end

  test "recommend fee tier for standard pair" do
    {:ok, r} = PriceOptimizer.recommend_fee_tier(%{volatility: :medium})
    assert r.recommended_tier == 3000
  end

  test "recommend fee tier for volatile pair" do
    {:ok, r} = PriceOptimizer.recommend_fee_tier(%{volatility: :high})
    assert r.recommended_tier == 10000
  end

  test "optimize tight range" do
    {:ok, r} = PriceOptimizer.optimize_range(%{current_price: 2000.0, strategy: :tight, volatility: :low})
    assert r.price_lower >= 1990
    assert r.price_upper <= 2010
    assert r.capital_efficiency >= 100
  end

  test "optimize wide range" do
    {:ok, r} = PriceOptimizer.optimize_range(%{current_price: 2000.0, strategy: :wide})
    assert r.price_lower < 1500
    assert r.price_upper > 2500
  end

  test "optimize balanced medium volatility" do
    {:ok, r} = PriceOptimizer.optimize_range(%{current_price: 100.0, volatility: :medium})
    assert r.range_width_pct == 20.0
  end

  test "calculate IL price up" do
    {:ok, r} = PriceOptimizer.calculate_il(100.0, 200.0)
    assert r.il_percentage > 0
    assert r.direction == :price_up
  end

  test "calculate IL price down" do
    {:ok, r} = PriceOptimizer.calculate_il(100.0, 50.0)
    assert r.il_percentage > 0
    assert r.direction == :price_down
  end

  test "no IL at same price" do
    {:ok, r} = PriceOptimizer.calculate_il(100.0, 100.0)
    assert r.il_percentage == 0.0
  end
end
