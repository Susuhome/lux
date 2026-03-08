defmodule Lux.Prisms.Discord.AgentDiscordTest do
  use ExUnit.Case, async: true

  alias Lux.Prisms.Discord.{ServerManagement, ConversationManager, MemberInteraction}

  # ServerManagement — test module functions exist with correct arity
  test "join_server/2" do
    assert function_exported?(ServerManagement, :join_server, 2)
  end

  test "leave_server/2" do
    assert function_exported?(ServerManagement, :leave_server, 2)
  end

  test "create_channel/3" do
    assert function_exported?(ServerManagement, :create_channel, 3)
  end

  test "create_role/3" do
    assert function_exported?(ServerManagement, :create_role, 3)
  end

  test "assign_role/4" do
    assert function_exported?(ServerManagement, :assign_role, 4)
  end

  test "remove_role/4" do
    assert function_exported?(ServerManagement, :remove_role, 4)
  end

  # ConversationManager
  test "create_thread/3" do
    assert function_exported?(ConversationManager, :create_thread, 3)
  end

  test "send_message/3" do
    assert function_exported?(ConversationManager, :send_message, 3)
  end

  test "add_reaction/4" do
    assert function_exported?(ConversationManager, :add_reaction, 4)
  end

  test "analyze history" do
    messages = [
      %{"author" => %{"id" => "1"}, "content" => "hi"},
      %{"author" => %{"id" => "2"}, "content" => "hello"},
      %{"author" => %{"id" => "1"}, "content" => "bye"}
    ]
    {:ok, analysis} = ConversationManager.analyze_history(messages)
    assert analysis.total_messages == 3
    assert analysis.unique_authors == 2
    assert analysis.author_counts["1"] == 2
  end

  # MemberInteraction
  test "kick_member/3" do
    assert function_exported?(MemberInteraction, :kick_member, 3)
  end

  test "ban_member/3" do
    assert function_exported?(MemberInteraction, :ban_member, 3)
  end

  test "nickname/4" do
    assert function_exported?(MemberInteraction, :nickname, 4)
  end

  test "send_dm/3" do
    assert function_exported?(MemberInteraction, :send_dm, 3)
  end
end
