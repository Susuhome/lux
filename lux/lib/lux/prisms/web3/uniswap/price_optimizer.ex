defmodule Lux.Prisms.Web3.Uniswap.PriceOptimizer do
  @moduledoc """
  Price range optimization and fee tier selection for Uniswap V3.
  """

  @fee_tiers %{
    100 => %{name: "0.01%", best_for: :stable_pairs, spread_multiplier: 1.001},
    500 => %{name: "0.05%", best_for: :correlated, spread_multiplier: 1.005},
    3000 => %{name: "0.3%", best_for: :standard, spread_multiplier: 1.03},
    10000 => %{name: "1%", best_for: :exotic, spread_multiplier: 1.10}
  }

  @doc "Recommend optimal fee tier based on pair characteristics."
  def recommend_fee_tier(params) do
    volatility = params[:volatility] || :medium
    correlation = params[:correlation] || 0.5
    volume = params[:daily_volume] || 0

    tier = cond do
      correlation > 0.95 -> 100
      correlation > 0.8 -> 500
      volatility == :low && volume > 1_000_000 -> 500
      volatility == :high -> 10000
      true -> 3000
    end

    {:ok, %{
      recommended_tier: tier,
      tier_info: @fee_tiers[tier],
      all_tiers: @fee_tiers,
      reasoning: fee_reasoning(tier, volatility, correlation)
    }}
  end

  @doc "Optimize price range for a position."
  def optimize_range(params) do
    current_price = params[:current_price]
    volatility = params[:volatility] || :medium
    strategy = params[:strategy] || :balanced

    {lower_mult, upper_mult} = case {strategy, volatility} do
      {:tight, :low} -> {0.995, 1.005}
      {:tight, _} -> {0.98, 1.02}
      {:balanced, :low} -> {0.95, 1.05}
      {:balanced, :medium} -> {0.90, 1.10}
      {:balanced, :high} -> {0.80, 1.20}
      {:wide, _} -> {0.70, 1.30}
      _ -> {0.90, 1.10}
    end

    price_lower = Float.round(current_price * lower_mult, 6)
    price_upper = Float.round(current_price * upper_mult, 6)

    capital_efficiency = Float.round(1 / (upper_mult - lower_mult), 2)

    {:ok, %{
      price_lower: price_lower,
      price_upper: price_upper,
      current_price: current_price,
      range_width_pct: Float.round((upper_mult - lower_mult) * 100, 2),
      capital_efficiency: capital_efficiency,
      strategy: strategy,
      estimated_apr_multiplier: capital_efficiency
    }}
  end

  @doc "Calculate impermanent loss for a price change."
  def calculate_il(initial_price, current_price) do
    ratio = current_price / initial_price
    il = 2 * :math.sqrt(ratio) / (1 + ratio) - 1
    {:ok, %{
      price_ratio: Float.round(ratio, 4),
      il_percentage: Float.round(abs(il) * 100, 4),
      direction: if(ratio >= 1, do: :price_up, else: :price_down)
    }}
  end

  defp fee_reasoning(100, _, _), do: "Stable pair - minimal fee captures tight spreads"
  defp fee_reasoning(500, _, _), do: "Correlated pair - low fee with moderate range"
  defp fee_reasoning(3000, _, _), do: "Standard pair - balanced fee for most trading pairs"
  defp fee_reasoning(10000, _, _), do: "Exotic/volatile pair - high fee compensates for IL risk"
  defp fee_reasoning(_, _, _), do: "Default recommendation"
end
