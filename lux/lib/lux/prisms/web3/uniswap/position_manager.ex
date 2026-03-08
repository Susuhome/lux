defmodule Lux.Prisms.Web3.Uniswap.PositionManager do
  @moduledoc """
  Manages Uniswap V3 concentrated liquidity positions.
  Handles creation, monitoring, rebalancing, and fee collection.
  """

  use GenServer

  defstruct [:positions, :fee_tiers, :config]

  @fee_tiers [100, 500, 3000, 10000]  # 0.01%, 0.05%, 0.3%, 1%

  def start_link(opts \\ []) do
    name = opts[:name] || __MODULE__
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def create_position(pid \\ __MODULE__, params) do
    GenServer.call(pid, {:create, params})
  end

  def close_position(pid \\ __MODULE__, position_id) do
    GenServer.call(pid, {:close, position_id})
  end

  def get_position(pid \\ __MODULE__, position_id) do
    GenServer.call(pid, {:get, position_id})
  end

  def list_positions(pid \\ __MODULE__) do
    GenServer.call(pid, :list)
  end

  def collect_fees(pid \\ __MODULE__, position_id) do
    GenServer.call(pid, {:collect_fees, position_id})
  end

  def rebalance(pid \\ __MODULE__, position_id, new_range) do
    GenServer.call(pid, {:rebalance, position_id, new_range})
  end

  def health_check(pid \\ __MODULE__, position_id) do
    GenServer.call(pid, {:health_check, position_id})
  end

  def portfolio_summary(pid \\ __MODULE__) do
    GenServer.call(pid, :portfolio_summary)
  end

  @impl true
  def init(opts) do
    {:ok, %__MODULE__{
      positions: %{},
      fee_tiers: @fee_tiers,
      config: %{
        rebalance_threshold: opts[:rebalance_threshold] || 0.1,
        auto_compound: opts[:auto_compound] || false
      }
    }}
  end

  @impl true
  def handle_call({:create, params}, _from, state) do
    id = gen_id()
    fee_tier = params[:fee_tier] || 3000

    unless fee_tier in @fee_tiers do
      {:reply, {:error, :invalid_fee_tier}, state}
    else
      position = %{
        id: id,
        pool: %{token0: params[:token0], token1: params[:token1], fee_tier: fee_tier},
        tick_lower: params[:tick_lower],
        tick_upper: params[:tick_upper],
        price_lower: params[:price_lower],
        price_upper: params[:price_upper],
        liquidity: params[:liquidity] || 0,
        amount0: params[:amount0] || 0,
        amount1: params[:amount1] || 0,
        fees_earned: %{token0: 0, token1: 0},
        status: :active,
        chain: params[:chain] || :ethereum,
        created_at: DateTime.utc_now()
      }
      {:reply, {:ok, position}, %{state | positions: Map.put(state.positions, id, position)}}
    end
  end

  @impl true
  def handle_call({:close, position_id}, _from, state) do
    case Map.get(state.positions, position_id) do
      nil -> {:reply, {:error, :not_found}, state}
      pos ->
        updated = %{pos | status: :closed}
        {:reply, {:ok, updated}, %{state | positions: Map.put(state.positions, position_id, updated)}}
    end
  end

  @impl true
  def handle_call({:get, position_id}, _from, state) do
    case Map.get(state.positions, position_id) do
      nil -> {:reply, {:error, :not_found}, state}
      pos -> {:reply, {:ok, pos}, state}
    end
  end

  @impl true
  def handle_call(:list, _from, state) do
    {:reply, {:ok, Map.values(state.positions)}, state}
  end

  @impl true
  def handle_call({:collect_fees, position_id}, _from, state) do
    case Map.get(state.positions, position_id) do
      nil -> {:reply, {:error, :not_found}, state}
      pos ->
        fees = pos.fees_earned
        updated = %{pos | fees_earned: %{token0: 0, token1: 0}}
        {:reply, {:ok, %{collected: fees, position_id: position_id}},
         %{state | positions: Map.put(state.positions, position_id, updated)}}
    end
  end

  @impl true
  def handle_call({:rebalance, position_id, new_range}, _from, state) do
    case Map.get(state.positions, position_id) do
      nil -> {:reply, {:error, :not_found}, state}
      pos ->
        updated = %{pos |
          tick_lower: new_range[:tick_lower] || pos.tick_lower,
          tick_upper: new_range[:tick_upper] || pos.tick_upper,
          price_lower: new_range[:price_lower] || pos.price_lower,
          price_upper: new_range[:price_upper] || pos.price_upper
        }
        {:reply, {:ok, updated}, %{state | positions: Map.put(state.positions, position_id, updated)}}
    end
  end

  @impl true
  def handle_call({:health_check, position_id}, _from, state) do
    case Map.get(state.positions, position_id) do
      nil -> {:reply, {:error, :not_found}, state}
      pos ->
        current_price = pos[:current_price] || (pos.price_lower + pos.price_upper) / 2
        in_range = current_price >= pos.price_lower && current_price <= pos.price_upper
        range_width = pos.price_upper - pos.price_lower
        range_utilization = if range_width > 0, do: Float.round((current_price - pos.price_lower) / range_width * 100, 1), else: 0.0

        health = %{
          position_id: position_id,
          in_range: in_range,
          status: pos.status,
          range_utilization: range_utilization,
          needs_rebalance: !in_range,
          impermanent_loss_estimate: estimate_il(pos, current_price)
        }
        {:reply, {:ok, health}, state}
    end
  end

  @impl true
  def handle_call(:portfolio_summary, _from, state) do
    positions = Map.values(state.positions)
    active = Enum.count(positions, &(&1.status == :active))
    total_fees_0 = Enum.sum(Enum.map(positions, &get_in(&1, [:fees_earned, :token0])))
    total_fees_1 = Enum.sum(Enum.map(positions, &get_in(&1, [:fees_earned, :token1])))

    {:reply, {:ok, %{
      total_positions: length(positions),
      active: active,
      closed: length(positions) - active,
      total_fees: %{token0: total_fees_0, token1: total_fees_1}
    }}, state}
  end

  defp estimate_il(pos, current_price) do
    mid = (pos.price_lower + pos.price_upper) / 2
    if mid > 0 do
      ratio = current_price / mid
      il = 2 * :math.sqrt(ratio) / (1 + ratio) - 1
      Float.round(abs(il) * 100, 2)
    else
      0.0
    end
  end

  defp gen_id, do: :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
end
