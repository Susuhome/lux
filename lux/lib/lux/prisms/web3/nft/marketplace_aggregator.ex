defmodule Lux.Prisms.Web3.NFT.MarketplaceAggregator do
  @moduledoc """
  NFT marketplace data aggregation: collection stats, floor prices, sales tracking, rarity analysis.
  """

  use GenServer

  defstruct [:collections, :sales, :watchlist]

  def start_link(opts \\ []) do
    name = opts[:name] || __MODULE__
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def track_collection(pid \\ __MODULE__, params), do: GenServer.call(pid, {:track, params})
  def untrack_collection(pid \\ __MODULE__, address), do: GenServer.call(pid, {:untrack, address})
  def get_collection(pid \\ __MODULE__, address), do: GenServer.call(pid, {:get, address})
  def list_collections(pid \\ __MODULE__), do: GenServer.call(pid, :list)
  def record_sale(pid \\ __MODULE__, sale), do: GenServer.call(pid, {:record_sale, sale})
  def get_sales(pid \\ __MODULE__, address), do: GenServer.call(pid, {:get_sales, address})
  def add_watchlist(pid \\ __MODULE__, params), do: GenServer.call(pid, {:watchlist_add, params})
  def get_watchlist(pid \\ __MODULE__), do: GenServer.call(pid, :watchlist)
  def analyze_rarity(traits), do: do_analyze_rarity(traits)
  def compare_collections(collections), do: do_compare(collections)

  @impl true
  def init(_opts), do: {:ok, %__MODULE__{collections: %{}, sales: %{}, watchlist: []}}

  @impl true
  def handle_call({:track, params}, _from, state) do
    addr = params[:address]
    collection = %{
      address: addr, name: params[:name], chain: params[:chain] || :ethereum,
      floor_price: params[:floor_price] || 0, total_supply: params[:total_supply] || 0,
      owners: params[:owners] || 0, volume_24h: params[:volume_24h] || 0,
      marketplace: params[:marketplace] || :opensea,
      tracked_at: DateTime.utc_now()
    }
    {:reply, {:ok, collection}, %{state | collections: Map.put(state.collections, addr, collection)}}
  end

  @impl true
  def handle_call({:untrack, address}, _from, state) do
    {:reply, :ok, %{state | collections: Map.delete(state.collections, address)}}
  end

  @impl true
  def handle_call({:get, address}, _from, state) do
    case Map.get(state.collections, address) do
      nil -> {:reply, {:error, :not_found}, state}
      c -> {:reply, {:ok, c}, state}
    end
  end

  @impl true
  def handle_call(:list, _from, state), do: {:reply, {:ok, Map.values(state.collections)}, state}

  @impl true
  def handle_call({:record_sale, sale}, _from, state) do
    entry = Map.merge(sale, %{id: gen_id(), at: DateTime.utc_now()})
    addr = sale[:collection]
    sales = Map.update(state.sales, addr, [entry], &[entry | Enum.take(&1, 999)])
    {:reply, {:ok, entry}, %{state | sales: sales}}
  end

  @impl true
  def handle_call({:get_sales, address}, _from, state) do
    {:reply, {:ok, Map.get(state.sales, address, [])}, state}
  end

  @impl true
  def handle_call({:watchlist_add, params}, _from, state) do
    entry = %{collection: params[:collection], floor_alert: params[:floor_alert], added_at: DateTime.utc_now()}
    {:reply, {:ok, entry}, %{state | watchlist: [entry | state.watchlist]}}
  end

  @impl true
  def handle_call(:watchlist, _from, state), do: {:reply, {:ok, state.watchlist}, state}

  defp do_analyze_rarity(traits) when is_list(traits) do
    total = length(traits)
    trait_counts = Enum.frequencies(traits)
    scores = Enum.map(trait_counts, fn {trait, count} ->
      {trait, Float.round(1 / (count / total), 4)}
    end)
    total_score = scores |> Enum.map(&elem(&1, 1)) |> Enum.sum() |> Float.round(2)
    {:ok, %{traits: Map.new(scores), total_score: total_score, rarity_rank: rank_rarity(total_score)}}
  end

  defp rank_rarity(score) when score > 50, do: :legendary
  defp rank_rarity(score) when score > 20, do: :rare
  defp rank_rarity(score) when score > 10, do: :uncommon
  defp rank_rarity(_), do: :common

  defp do_compare(collections) when is_list(collections) do
    sorted = Enum.sort_by(collections, & &1[:floor_price] || 0, :desc)
    avg_floor = if length(collections) > 0, do: Enum.sum(Enum.map(collections, & &1[:floor_price] || 0)) / length(collections), else: 0
    {:ok, %{ranked: sorted, avg_floor: Float.round(avg_floor, 4), count: length(collections)}}
  end

  defp gen_id, do: :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
end
