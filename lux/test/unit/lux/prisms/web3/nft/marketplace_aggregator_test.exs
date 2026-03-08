defmodule Lux.Prisms.Web3.NFT.MarketplaceAggregatorTest do
  use ExUnit.Case, async: true
  alias Lux.Prisms.Web3.NFT.MarketplaceAggregator

  setup do
    name = :"nft_#{:rand.uniform(1_000_000)}"
    {:ok, pid} = MarketplaceAggregator.start_link(name: name)
    %{pid: pid}
  end

  test "track collection", %{pid: pid} do
    {:ok, c} = MarketplaceAggregator.track_collection(pid, %{address: "0xbc4ca", name: "BAYC", floor_price: 30.5})
    assert c.name == "BAYC"
  end

  test "get collection", %{pid: pid} do
    {:ok, _} = MarketplaceAggregator.track_collection(pid, %{address: "0xabc", name: "Test"})
    {:ok, c} = MarketplaceAggregator.get_collection(pid, "0xabc")
    assert c.name == "Test"
  end

  test "untrack", %{pid: pid} do
    {:ok, _} = MarketplaceAggregator.track_collection(pid, %{address: "0x1"})
    :ok = MarketplaceAggregator.untrack_collection(pid, "0x1")
    assert {:error, :not_found} = MarketplaceAggregator.get_collection(pid, "0x1")
  end

  test "record and get sales", %{pid: pid} do
    {:ok, _} = MarketplaceAggregator.record_sale(pid, %{collection: "0xabc", token_id: 1, price: 5.0})
    {:ok, _} = MarketplaceAggregator.record_sale(pid, %{collection: "0xabc", token_id: 2, price: 6.0})
    {:ok, sales} = MarketplaceAggregator.get_sales(pid, "0xabc")
    assert length(sales) == 2
  end

  test "watchlist", %{pid: pid} do
    {:ok, _} = MarketplaceAggregator.add_watchlist(pid, %{collection: "BAYC", floor_alert: 25.0})
    {:ok, wl} = MarketplaceAggregator.get_watchlist(pid)
    assert length(wl) == 1
  end

  test "analyze rarity" do
    {:ok, r} = MarketplaceAggregator.analyze_rarity(["blue", "red", "blue", "green", "blue", "red"])
    assert r.total_score > 0
    assert r.rarity_rank in [:common, :uncommon, :rare, :legendary]
  end

  test "compare collections" do
    collections = [%{name: "A", floor_price: 10}, %{name: "B", floor_price: 30}, %{name: "C", floor_price: 5}]
    {:ok, r} = MarketplaceAggregator.compare_collections(collections)
    assert hd(r.ranked).floor_price == 30
    assert r.avg_floor == 15.0
  end

  test "list collections", %{pid: pid} do
    {:ok, _} = MarketplaceAggregator.track_collection(pid, %{address: "0x1"})
    {:ok, list} = MarketplaceAggregator.list_collections(pid)
    assert length(list) == 1
  end
end
