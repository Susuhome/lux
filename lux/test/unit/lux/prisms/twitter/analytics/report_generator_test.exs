defmodule Lux.Prisms.Twitter.Analytics.ReportGeneratorTest do
  use ExUnit.Case, async: true

  alias Lux.Prisms.Twitter.Analytics.{MetricsCollector, ReportGenerator}

  test "generate full report" do
    name = :"rpt_#{:rand.uniform(1_000_000)}"
    {:ok, pid} = MetricsCollector.start_link(name: name)
    MetricsCollector.track_tweet(pid, %{id: "t1", text: "#ai is cool", likes: 50, retweets: 20, replies: 5, quotes: 2, impressions: 3000})
    MetricsCollector.track_follower_count(pid, 1000)
    Process.sleep(10)

    {:ok, report} = ReportGenerator.generate(pid)
    assert report.overview.total_tweets == 1
    assert length(report.top_tweets) >= 1
    assert report.generated_at
  end

  test "sentiment report" do
    texts = [
      "I love this amazing product!",
      "Terrible customer service, horrible experience",
      "The update is okay I guess"
    ]
    {:ok, report} = ReportGenerator.sentiment_report(texts)
    assert report.summary.total == 3
    assert length(report.samples) == 3
  end
end
