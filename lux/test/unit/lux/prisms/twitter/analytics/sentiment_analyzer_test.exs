defmodule Lux.Prisms.Twitter.Analytics.SentimentAnalyzerTest do
  use ExUnit.Case, async: true

  alias Lux.Prisms.Twitter.Analytics.SentimentAnalyzer

  test "positive sentiment" do
    result = SentimentAnalyzer.analyze("This is amazing and wonderful!")
    assert result.sentiment == :positive
    assert result.score > 0
    assert result.positive_count >= 2
  end

  test "negative sentiment" do
    result = SentimentAnalyzer.analyze("This is terrible and horrible")
    assert result.sentiment == :negative
    assert result.score < 0
  end

  test "neutral sentiment" do
    result = SentimentAnalyzer.analyze("The weather is normal today")
    assert result.sentiment == :neutral
  end

  test "empty text" do
    result = SentimentAnalyzer.analyze("")
    assert result.sentiment == :neutral
    assert result.score == 0.0
  end

  test "batch analysis" do
    texts = [
      "This is amazing!",
      "Terrible experience",
      "Just a regular day",
      "Love this product, it's great!"
    ]
    result = SentimentAnalyzer.analyze_batch(texts)
    assert result.total == 4
    assert result.positive >= 1
    assert result.negative >= 1
    assert result.distribution.positive + result.distribution.negative + result.distribution.neutral == 100.0
  end

  test "batch empty list" do
    result = SentimentAnalyzer.analyze_batch([])
    assert result.total == 0
  end
end
