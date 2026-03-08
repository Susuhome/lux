defmodule Lux.Lenses.Coinbase.MarketHistory do
  @moduledoc """
  Lens for Coinbase historical market data (candles/OHLCV).
  """

  alias Lux.Integrations.Coinbase.Client

  @valid_granularities ~w(ONE_MINUTE FIVE_MINUTE FIFTEEN_MINUTE THIRTY_MINUTE ONE_HOUR TWO_HOUR SIX_HOUR ONE_DAY)

  @spec get_candles(String.t(), keyword() | map()) :: {:ok, list(map())} | {:error, term()}
  def get_candles(product_id, opts \\ %{}) do
    params =
      %{}
      |> maybe_put(:start, opts[:start])
      |> maybe_put(:end, opts[:end])
      |> maybe_put(:granularity, opts[:granularity] || "ONE_HOUR")

    case Client.request(:get, "/products/#{product_id}/candles", Map.put(opts, :params, params)) do
      {:ok, %{"candles" => candles}} -> {:ok, Enum.map(candles, &format_candle/1)}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Returns valid granularity options for candle data.
  """
  def valid_granularities, do: @valid_granularities

  defp format_candle(c) do
    %{
      start: c["start"],
      low: c["low"],
      high: c["high"],
      open: c["open"],
      close: c["close"],
      volume: c["volume"]
    }
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
