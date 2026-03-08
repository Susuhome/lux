defmodule Lux.Signals.Discord.SignalsTest do
  use ExUnit.Case, async: true

  alias Lux.Signals.Discord.{MessageSignal, InteractionSignal, PresenceSignal, Pipeline}

  # MessageSignal
  test "create message signal" do
    {:ok, sig} = MessageSignal.new(%{content: "hello", channel_id: "123"})
    assert sig.content == "hello"
    assert sig.channel_id == "123"
  end

  test "message signal requires content" do
    assert {:error, :content_required} = MessageSignal.new(%{})
  end

  test "message to discord" do
    {:ok, sig} = MessageSignal.new(%{content: "hi", channel_id: "1"})
    discord = MessageSignal.to_discord(sig)
    assert discord["content"] == "hi"
  end

  test "message from discord" do
    {:ok, sig} = MessageSignal.from_discord(%{"content" => "test", "channel_id" => "456", "author" => %{"id" => "1"}})
    assert sig.content == "test"
    assert sig.author["id"] == "1"
  end

  test "validate message" do
    {:ok, sig} = MessageSignal.new(%{content: "ok"})
    assert :ok = MessageSignal.validate(sig)
  end

  # InteractionSignal
  test "create interaction signal" do
    {:ok, sig} = InteractionSignal.new(%{type: :slash_command, name: "/ping"})
    assert sig.type == :slash_command
    assert sig.name == "/ping"
  end

  test "invalid interaction type" do
    assert {:error, :invalid_interaction_type} = InteractionSignal.new(%{type: :invalid})
  end

  test "interaction to discord" do
    {:ok, sig} = InteractionSignal.new(%{type: :slash_command, name: "test"})
    discord = InteractionSignal.to_discord(sig)
    assert discord["type"] == 2
  end

  test "interaction from discord" do
    {:ok, sig} = InteractionSignal.from_discord(%{"type" => 2, "data" => %{"name" => "help"}, "channel_id" => "1"})
    assert sig.name == "help"
  end

  # PresenceSignal
  test "create presence signal" do
    {:ok, sig} = PresenceSignal.new(%{user_id: "1", status: :online, activities: [%{name: "Playing"}]})
    assert sig.status == :online
    assert length(sig.activities) == 1
  end

  test "invalid presence status" do
    assert {:error, :invalid_status} = PresenceSignal.new(%{status: :invalid})
  end

  test "presence to discord" do
    {:ok, sig} = PresenceSignal.new(%{user_id: "1", status: :idle})
    discord = PresenceSignal.to_discord(sig)
    assert discord["status"] == "idle"
  end

  test "presence from discord" do
    {:ok, sig} = PresenceSignal.from_discord(%{"user" => %{"id" => "1"}, "status" => "online", "activities" => []})
    assert sig.status == :online
  end

  # Pipeline
  test "classify message" do
    assert {:ok, :message} = Pipeline.classify(%{"content" => "hi"})
  end

  test "classify interaction" do
    assert {:ok, :interaction} = Pipeline.classify(%{"type" => 2})
  end

  test "classify presence" do
    assert {:ok, :presence} = Pipeline.classify(%{"status" => "online"})
  end

  test "classify unknown" do
    assert {:error, :unknown_signal} = Pipeline.classify(%{"random" => true})
  end

  test "parse message payload" do
    {:ok, sig} = Pipeline.parse(%{"content" => "hello"})
    assert %MessageSignal{} = sig
  end

  test "process pipeline" do
    {:ok, sig} = MessageSignal.new(%{content: "hello"})
    step = fn s -> {:ok, %{s | content: String.upcase(s.content)}} end
    {:ok, result} = Pipeline.process(sig, [step])
    assert result.content == "HELLO"
  end

  test "pipeline halts on error" do
    {:ok, sig} = MessageSignal.new(%{content: "hello"})
    fail = fn _s -> {:error, :boom} end
    ok = fn s -> {:ok, s} end
    assert {:error, :boom} = Pipeline.process(sig, [fail, ok])
  end
end
