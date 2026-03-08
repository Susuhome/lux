defmodule Lux.Prisms.Web3.PancakeSwap.FarmManager do
  @moduledoc """
  PancakeSwap integration: swap, liquidity, yield farming, CAKE staking.
  """

  use GenServer

  defstruct [:farms, :pools, :staking]

  def start_link(opts \\ []) do
    name = opts[:name] || __MODULE__
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def add_farm(pid \\ __MODULE__, params), do: GenServer.call(pid, {:add_farm, params})
  def remove_farm(pid \\ __MODULE__, farm_id), do: GenServer.call(pid, {:remove_farm, farm_id})
  def stake_cake(pid \\ __MODULE__, amount), do: GenServer.call(pid, {:stake_cake, amount})
  def unstake_cake(pid \\ __MODULE__, amount), do: GenServer.call(pid, {:unstake_cake, amount})
  def harvest(pid \\ __MODULE__, farm_id), do: GenServer.call(pid, {:harvest, farm_id})
  def list_farms(pid \\ __MODULE__), do: GenServer.call(pid, :list_farms)
  def get_staking(pid \\ __MODULE__), do: GenServer.call(pid, :get_staking)
  def estimate_swap(params), do: do_estimate_swap(params)
  def analyze_farm(params), do: do_analyze_farm(params)

  @impl true
  def init(_opts), do: {:ok, %__MODULE__{farms: %{}, pools: %{}, staking: %{staked: 0, rewards: 0}}}

  @impl true
  def handle_call({:add_farm, params}, _from, state) do
    id = gen_id()
    farm = %{
      id: id, pair: params[:pair], lp_amount: params[:lp_amount] || 0,
      rewards_earned: 0, apr: params[:apr] || 0, multiplier: params[:multiplier] || "1x",
      chain: params[:chain] || :bsc, status: :active, created_at: DateTime.utc_now()
    }
    {:reply, {:ok, farm}, %{state | farms: Map.put(state.farms, id, farm)}}
  end

  @impl true
  def handle_call({:remove_farm, farm_id}, _from, state) do
    case Map.get(state.farms, farm_id) do
      nil -> {:reply, {:error, :not_found}, state}
      farm ->
        updated = %{farm | status: :withdrawn}
        {:reply, {:ok, updated}, %{state | farms: Map.put(state.farms, farm_id, updated)}}
    end
  end

  @impl true
  def handle_call({:stake_cake, amount}, _from, state) do
    staking = %{state.staking | staked: state.staking.staked + amount}
    {:reply, {:ok, staking}, %{state | staking: staking}}
  end

  @impl true
  def handle_call({:unstake_cake, amount}, _from, state) do
    actual = min(amount, state.staking.staked)
    staking = %{state.staking | staked: state.staking.staked - actual}
    {:reply, {:ok, %{unstaked: actual, remaining: staking.staked}}, %{state | staking: staking}}
  end

  @impl true
  def handle_call({:harvest, farm_id}, _from, state) do
    case Map.get(state.farms, farm_id) do
      nil -> {:reply, {:error, :not_found}, state}
      farm ->
        rewards = farm.rewards_earned
        updated = %{farm | rewards_earned: 0}
        {:reply, {:ok, %{harvested: rewards}}, %{state | farms: Map.put(state.farms, farm_id, updated)}}
    end
  end

  @impl true
  def handle_call(:list_farms, _from, state) do
    {:reply, {:ok, Map.values(state.farms)}, state}
  end

  @impl true
  def handle_call(:get_staking, _from, state) do
    {:reply, {:ok, state.staking}, state}
  end

  defp do_estimate_swap(params) do
    amount_in = params[:amount_in] || 0
    fee_rate = params[:fee_rate] || 0.0025
    slippage = params[:slippage] || 0.005
    price = params[:price] || 1.0

    amount_out = amount_in * price * (1 - fee_rate) * (1 - slippage)
    {:ok, %{amount_in: amount_in, amount_out: Float.round(amount_out, 6), fee: Float.round(amount_in * fee_rate, 6), price_impact: slippage * 100}}
  end

  defp do_analyze_farm(params) do
    apr = params[:apr] || 0
    tvl = params[:tvl] || 0
    multiplier = params[:multiplier] || "1x"

    risk = cond do
      tvl > 10_000_000 -> :low
      tvl > 1_000_000 -> :medium
      true -> :high
    end

    {:ok, %{apr: apr, tvl: tvl, multiplier: multiplier, risk: risk, daily_yield: Float.round(apr / 365, 4)}}
  end

  defp gen_id, do: :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
end
