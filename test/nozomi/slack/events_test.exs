defmodule NozomiStation.Slack.EventsTest do
  use ExUnit.Case, async: true

  alias NozomiStation.Slack.Signature

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
end
