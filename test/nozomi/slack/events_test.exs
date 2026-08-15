defmodule NozomiStation.Slack.EventsTest do
  use NozomiStation.DataCase, async: true

  alias NozomiStation.Slack.{EventStore, Events, Signature}

  @body ~s({"type":"event_callback","event_id":"Ev01"})
  @secret "test-signing-secret"
  @timestamp "1700000000"
  @signature "v0=b64dc277db0ae596c9e60e1f1125bd001baf8b72de6c61b5c31b0cad05d45c39"

  test "accepts a current request signed over its raw body" do
    assert Signature.valid?(@body, @timestamp, @signature, @secret, 1_700_000_100)
  end

  test "rejects stale, malformed, and altered signatures" do
    refute Signature.valid?(@body, @timestamp, @signature, @secret, 1_700_000_301)
    refute Signature.valid?(@body <> " ", @timestamp, @signature, @secret, 1_700_000_100)
    refute Signature.valid?(@body, "invalid", @signature, @secret, 1_700_000_100)
  end

  test "persists an event_id once" do
    event = %{"event_id" => "Ev-persisted", "event" => %{"text" => "hello"}}

    assert {:ok, stored} = EventStore.insert(event)
    assert stored.event_id == "Ev-persisted"
    assert stored.payload == event
    assert EventStore.insert(event) == :duplicate
  end

  test "enqueues only the first delivery of an event" do
    {:ok, seen} = Agent.start_link(fn -> MapSet.new() end)

    store = fn event ->
      Agent.get_and_update(seen, fn ids ->
        if MapSet.member?(ids, event["event_id"]) do
          {:duplicate, ids}
        else
          {{:ok, event}, MapSet.put(ids, event["event_id"])}
        end
      end)
    end

    enqueue = fn event -> send(self(), {:enqueued, event["event_id"]}) end
    event = %{"event_id" => "Ev01"}

    assert Events.accept(event, store, enqueue) == :accepted
    assert_receive {:enqueued, "Ev01"}
    assert Events.accept(event, store, enqueue) == :duplicate
    refute_receive {:enqueued, "Ev01"}
  end
end
