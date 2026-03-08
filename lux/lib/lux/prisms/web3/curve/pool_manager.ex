defmodule Lux.Prisms.Web3.Curve.PoolManager do
  @moduledoc """
  Curve Finance stablecoin pool management: positions, gauge staking, CRV rewards.
  """

  use GenServer

  defstruct [:positions, :gauges, :rewards]

  def start_link(opts \\ []) do
    name = opts[:name] || __MODULE__
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def add_liquidity(pid \\ __MODULE__, params), do: GenServer.call(pid, {:add_liquidity, params})
  def remove_liquidity(pid \\ __MODULE__, position_id, pct \\ 100), do: GenServer.call(pid, {:remove_liquidity, position_id, pct})
  def stake_gauge(pid \\ __MODULE__, position_id), do: GenServer.call(pid, {:stake_gauge, position_id})
  def unstake_gauge(pid \\ __MODULE__, position_id), do: GenServer.call(pid, {:unstake_gauge, position_id})
  def claim_rewards(pid \\ __MODULE__, position_id), do: GenServer.call(pid, {:claim_rewards, position_id})
  def get_position(pid \\ __MODULE__, position_id), do: GenServer.call(pid, {:get, position_id})
  def list_positions(pid \\ __MODULE__), do: GenServer.call(pid, :list)
  def analyze_pool(params), do: do_analyze_pool(params)

  @impl true
  def init(_opts), do: {:ok, %__MODULE__{positions: %{}, gauges: %{}, rewards: %{}}}

  @impl true
  def handle_call({:add_liquidity, params}, _from, state) do
    id = gen_id()
    position = %{
      id: id, pool: params[:pool], tokens: params[:tokens] || [],
      amounts: params[:amounts] || [], lp_tokens: params[:lp_amount] || 0,
      staked: false, rewards_earned: %{crv: 0, extra: []},
      status: :active, created_at: DateTime.utc_now()
    }
    {:reply, {:ok, position}, %{state | positions: Map.put(state.positions, id, position)}}
  end

  @impl true
  def handle_call({:remove_liquidity, pos_id, pct}, _from, state) do
    with_position(state, pos_id, fn pos ->
      removed = Float.round(pos.lp_tokens * pct / 100, 6)
      remaining = Float.round(pos.lp_tokens - removed, 6)
      updated = if remaining <= 0, do: %{pos | lp_tokens: 0, status: :closed}, else: %{pos | lp_tokens: remaining}
      {:ok, %{removed_lp: removed, remaining_lp: remaining, position: updated}, put_pos(state, pos_id, updated)}
    end)
  end

  @impl true
  def handle_call({:stake_gauge, pos_id}, _from, state) do
    with_position(state, pos_id, fn pos ->
      updated = %{pos | staked: true}
      {:ok, updated, put_pos(state, pos_id, updated)}
    end)
  end

  @impl true
  def handle_call({:unstake_gauge, pos_id}, _from, state) do
    with_position(state, pos_id, fn pos ->
      updated = %{pos | staked: false}
      {:ok, updated, put_pos(state, pos_id, updated)}
    end)
  end

  @impl true
  def handle_call({:claim_rewards, pos_id}, _from, state) do
    with_position(state, pos_id, fn pos ->
      rewards = pos.rewards_earned
      updated = %{pos | rewards_earned: %{crv: 0, extra: []}}
      {:ok, %{claimed: rewards}, put_pos(state, pos_id, updated)}
    end)
  end

  @impl true
  def handle_call({:get, pos_id}, _from, state) do
    case Map.get(state.positions, pos_id) do
      nil -> {:reply, {:error, :not_found}, state}
      pos -> {:reply, {:ok, pos}, state}
    end
  end

  @impl true
  def handle_call(:list, _from, state) do
    {:reply, {:ok, Map.values(state.positions)}, state}
  end

  defp do_analyze_pool(params) do
    tvl = params[:tvl] || 0
    volume_24h = params[:volume_24h] || 0
    fee_rate = params[:fee_rate] || 0.0004
    num_tokens = params[:num_tokens] || 2

    daily_fees = volume_24h * fee_rate
    apr = if tvl > 0, do: Float.round(daily_fees * 365 / tvl * 100, 2), else: 0.0
    utilization = if tvl > 0, do: Float.round(volume_24h / tvl * 100, 2), else: 0.0

    {:ok, %{
      apr_estimate: apr,
      daily_fees: Float.round(daily_fees, 2),
      utilization: utilization,
      risk_score: risk_score(tvl, num_tokens),
      recommendation: if(apr > 5, do: :attractive, else: :moderate)
    }}
  end

  defp risk_score(tvl, num_tokens) do
    base = cond do
      tvl > 100_000_000 -> 10
      tvl > 10_000_000 -> 30
      tvl > 1_000_000 -> 50
      true -> 80
    end
    base + (num_tokens - 2) * 5
  end

  defp with_position(state, pos_id, fun) do
    case Map.get(state.positions, pos_id) do
      nil -> {:reply, {:error, :not_found}, state}
      pos ->
        {_ok_tag, data, new_state} = fun.(pos)
        {:reply, {:ok, data}, new_state}
    end
  end

  defp put_pos(state, id, pos), do: %{state | positions: Map.put(state.positions, id, pos)}
  defp gen_id, do: :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
end
