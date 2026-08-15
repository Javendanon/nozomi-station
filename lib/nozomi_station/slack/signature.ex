defmodule NozomiStation.Slack.Signature do
  @max_age_seconds 300

  def valid?(body, timestamp, signature, secret, now \\ System.system_time(:second))

  def valid?(body, timestamp, signature, secret, now)
      when is_binary(body) and is_binary(timestamp) and is_binary(signature) and
             is_binary(secret) do
    with {sent_at, ""} <- Integer.parse(timestamp),
         true <- abs(now - sent_at) <= @max_age_seconds do
      expected =
        "v0=" <>
          (:crypto.mac(:hmac, :sha256, secret, "v0:#{timestamp}:#{body}")
           |> Base.encode16(case: :lower))

      byte_size(expected) == byte_size(signature) and
        Plug.Crypto.secure_compare(expected, signature)
    else
      _ -> false
    end
  end

  def valid?(_, _, _, _, _), do: false
end
