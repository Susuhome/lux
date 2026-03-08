defmodule Lux.Lenses.Coinbase.MarketHistoryTest do
  use UnitAPICase, async: true

  alias Lux.Lenses.Coinbase.MarketHistory
  alias Lux.Integrations.Coinbase.Client

  setup do
    Req.Test.verify_on_exit!()
    :ok
  end

  describe "get_candles/2" do
    test "returns formatted candle data" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/api/v3/brokerage/products/BTC-USD/candles"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{
          "candles" => [
            %{"start" => "1709856000", "low" => "67000", "high" => "68500",
              "open" => "67500", "close" => "68200", "volume" => "1234.56"},
            %{"start" => "1709852400", "low" => "66800", "high" => "67600",
              "open" => "67000", "close" => "67500", "volume" => "987.65"}
          ]
        }))
      end)

      assert {:ok, candles} = MarketHistory.get_candles("BTC-USD")
      assert length(candles) == 2
      assert hd(candles).open == "67500"
      assert hd(candles).close == "68200"
      assert hd(candles).volume == "1234.56"
    end

    test "passes granularity parameter" do
      Req.Test.stub(Client, fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["granularity"] == "FIVE_MINUTE"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{"candles" => []}))
      end)

      assert {:ok, []} = MarketHistory.get_candles("ETH-USD", %{granularity: "FIVE_MINUTE"})
    end

    test "handles error response" do
      Req.Test.stub(Client, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(400, Jason.encode!(%{"error" => "NOT_FOUND", "message" => "Product not found"}))
      end)

      assert {:error, {400, "NOT_FOUND: Product not found"}} = MarketHistory.get_candles("INVALID")
    end
  end

  describe "valid_granularities/0" do
    test "returns list of valid granularity options" do
      granularities = MarketHistory.valid_granularities()
      assert is_list(granularities)
      assert "ONE_HOUR" in granularities
      assert "ONE_DAY" in granularities
    end
  end
end
