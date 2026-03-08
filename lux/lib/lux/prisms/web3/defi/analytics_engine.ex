defmodule Lux.Prisms.Web3.DeFi.AnalyticsEngine do
  @moduledoc """
  DeFi analytics: protocol TVL tracking, yield comparison, risk scoring, portfolio analysis.
  """

  use GenServer

  defstruct [:protocols, :snapshots, :portfolio]

  def start_link(opts \\ []) do
    name = opts[:name] || __MODULE__
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def track_protocol(pid \\ __MODULE__, params), do: GenServer.call(pid, {:track, params})
  def update_tvl(pid \\ __MODULE__, protocol_id, tvl), do: GenServer.call(pid, {:update_tvl, protocol_id, tvl})
  def list_protocols(pid \\ __MODULE__), do: GenServer.call(pid, :list)
  def get_protocol(pid \\ __MODULE__, protocol_id), do: GenServer.call(pid, {:get, protocol_id})
  def add_to_portfolio(pid \\ __MODULE__, params), do: GenServer.call(pid, {:portfolio_add, params})
  def portfolio_summary(pid \\ __MODULE__), do: GenServer.call(pid, :portfolio_summary)
  def compare_yields(protocols), do: do_compare_yields(protocols)
  def risk_score(params), do: do_risk_score(params)

  @impl true
  def init(_opts), do: {:ok, %__MODULE__{protocols: %{}, snapshots: %{}, portfolio: []}}

  @impl true
  def handle_call({:track, params}, _from, state) do
    id = params[:id] || params[:name] || gen_id()
    protocol = %{
      id: id, name: params[:name], category: params[:category] || :lending,
      chain: params[:chain] || :ethereum, tvl: params[:tvl] || 0,
      apy: params[:apy] || 0, token: params[:token],
      audited: params[:audited] || false,
      tracked_at: DateTime.utc_now()
    }
    {:reply, {:ok, protocol}, %{state | protocols: Map.put(state.protocols, id, protocol)}}
  end

  @impl true
  def handle_call({:update_tvl, pid, tvl}, _from, state) do
    case Map.get(state.protocols, pid) do
      nil -> {:reply, {:error, :not_found}, state}
      protocol ->
        updated = %{protocol | tvl: tvl}
        snapshot = %{protocol_id: pid, tvl: tvl, at: DateTime.utc_now()}
        snapshots = Map.update(state.snapshots, pid, [snapshot], &[snapshot | Enum.take(&1, 99)])
        {:reply, {:ok, updated}, %{state | protocols: Map.put(state.protocols, pid, updated), snapshots: snapshots}}
    end
  end

  @impl true
  def handle_call(:list, _from, state), do: {:reply, {:ok, Map.values(state.protocols)}, state}

  @impl true
  def handle_call({:get, pid}, _from, state) do
    case Map.get(state.protocols, pid) do
      nil -> {:reply, {:error, :not_found}, state}
      p -> {:reply, {:ok, p}, state}
    end
  end

  @impl true
  def handle_call({:portfolio_add, params}, _from, state) do
    entry = %{protocol: params[:protocol], amount: params[:amount] || 0, apy: params[:apy] || 0, added_at: DateTime.utc_now()}
    {:reply, {:ok, entry}, %{state | portfolio: [entry | state.portfolio]}}
  end

  @impl true
  def handle_call(:portfolio_summary, _from, state) do
    total = Enum.sum(Enum.map(state.portfolio, & &1.amount))
    weighted_apy = if total > 0 do
      Enum.sum(Enum.map(state.portfolio, fn e -> e.amount * e.apy end)) / total
    else
      0.0
    end

    {:reply, {:ok, %{
      total_value: total,
      positions: length(state.portfolio),
      weighted_apy: Float.round(weighted_apy, 2),
      daily_yield: Float.round(total * weighted_apy / 100 / 365, 2)
    }}, state}
  end

  defp do_compare_yields(protocols) when is_list(protocols) do
    sorted = Enum.sort_by(protocols, & &1[:apy] || 0, :desc)
    {:ok, %{
      ranked: Enum.map(sorted, &Map.take(&1, [:name, :apy, :tvl, :chain])),
      best: hd(sorted)[:name],
      avg_apy: Float.round(Enum.sum(Enum.map(protocols, & &1[:apy] || 0)) / max(length(protocols), 1), 2)
    }}
  end

  defp do_risk_score(params) do
    score = 0
    score = score + if(params[:audited], do: 0, else: 30)
    score = score + if((params[:tvl] || 0) > 100_000_000, do: 0, else: if((params[:tvl] || 0) > 10_000_000, do: 10, else: 30))
    score = score + if((params[:age_days] || 0) > 365, do: 0, else: if((params[:age_days] || 0) > 90, do: 10, else: 20))
    score = score + if((params[:apy] || 0) > 100, do: 30, else: if((params[:apy] || 0) > 30, do: 10, else: 0))

    level = cond do
      score >= 60 -> :high
      score >= 30 -> :medium
      true -> :low
    end

    {:ok, %{score: score, level: level, max_score: 110}}
  end

  defp gen_id, do: :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
end
