defmodule NozomiStation.Slack.EventsTest do
  use NozomiStation.DataCase, async: true

  alias NozomiStation.Slack.{EventStore, Signature}

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
    refute Signature.valid?(nil, @timestamp, @signature, @secret, 1_700_000_100)
  end

  test "persists an event_id once" do
    event = %{"event_id" => "Ev-persisted", "event" => %{"text" => "hello"}}

    assert {:ok, stored} = EventStore.insert(event)
    assert stored.event_id == "Ev-persisted"
    assert stored.payload == event
    assert EventStore.insert(event) == :duplicate
  end

  test "rolls back event acceptance when enqueueing fails" do
    event = %{"event_id" => "Ev-rollback", "event" => %{"text" => "hello"}}

    assert {:error, :queue_unavailable} =
             EventStore.accept(event, fn _stored -> {:error, :queue_unavailable} end)

    assert :accepted = EventStore.accept(event, fn _stored -> {:ok, %{id: 1}} end)
  end
end
