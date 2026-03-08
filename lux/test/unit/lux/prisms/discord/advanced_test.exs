defmodule Lux.Prisms.Discord.AdvancedTest do
  use ExUnit.Case, async: true

  alias Lux.Prisms.Discord.{VoiceChannel, RichPresence, WebhookManager, ServerAnalytics}

  # VoiceChannel
  test "voice channel functions exist" do
    assert function_exported?(VoiceChannel, :join, 3)
    assert function_exported?(VoiceChannel, :leave, 2)
    assert function_exported?(VoiceChannel, :get_regions, 1)
  end

  # RichPresence
  test "create rich presence" do
    {:ok, rp} = RichPresence.new(%{name: "Testing", type: :playing, state: "In Lux"})
    assert rp.name == "Testing"
    assert rp.type == 0
  end

  test "rich presence to payload" do
    {:ok, rp} = RichPresence.new(%{name: "Bot", type: :streaming, url: "https://twitch.tv/test"})
    payload = RichPresence.to_payload(rp)
    assert payload["name"] == "Bot"
    assert payload["type"] == 1
    assert payload["url"] == "https://twitch.tv/test"
    refute Map.has_key?(payload, "state")
  end

  test "activity types" do
    types = RichPresence.activity_types()
    assert types[:playing] == 0
    assert types[:competing] == 5
  end

  # WebhookManager
  test "webhook functions exist" do
    assert function_exported?(WebhookManager, :create, 3)
    assert function_exported?(WebhookManager, :delete, 2)
    assert function_exported?(WebhookManager, :list, 2)
  end

  test "execute webhook returns payload" do
    {:ok, result} = WebhookManager.execute("wh_123", "token_abc", %{content: "Hello!"})
    assert result.body.content == "Hello!"
    assert result.url =~ "wh_123"
  end

  # ServerAnalytics
  test "analyze activity" do
    messages = [
      %{channel_id: "1", hour: 10},
      %{channel_id: "1", hour: 10},
      %{channel_id: "2", hour: 15}
    ]
    {:ok, result} = ServerAnalytics.analyze_activity(messages)
    assert result.total == 3
    assert result.by_channel["1"] == 2
    assert result.by_hour[10] == 2
  end

  test "member stats" do
    members = [%{bot: false}, %{bot: true}, %{bot: false}, %{bot: false}]
    {:ok, stats} = ServerAnalytics.member_stats(members)
    assert stats.total == 4
    assert stats.bots == 1
    assert stats.humans == 3
  end

  test "growth rate" do
    {:ok, result} = ServerAnalytics.growth_rate([100, 110, 120])
    assert result.rate == 20.0
    assert result.from == 100
    assert result.to == 120
  end

  test "growth rate insufficient data" do
    assert {:error, :insufficient_data} = ServerAnalytics.growth_rate([100])
  end
end
