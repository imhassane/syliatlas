defmodule SyliAtlas.Accounts.Secrets do
  @moduledoc """
  Codes, tokens and what is stored in their place.

    * Codes and email addresses are stored as HMAC-SHA256 with a server
      secret derived from `secret_key_base`: a copy of the database reveals
      neither, and a 6-digit code cannot be found offline without the secret.
    * Session tokens are 32 random bytes; their SHA-256 is stored.
  """

  @spec generate_code() :: String.t()
  def generate_code do
    # Rejection sampling: uniform over 000000..999999, no modulo bias.
    <<value::unsigned-32>> = :crypto.strong_rand_bytes(4)
    limit = div(0xFFFFFFFF, 1_000_000) * 1_000_000

    if value < limit do
      value |> rem(1_000_000) |> Integer.to_string() |> String.pad_leading(6, "0")
    else
      generate_code()
    end
  end

  def generate_token, do: Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
  def hash_token(token), do: :crypto.hash(:sha256, token)

  @doc "HMAC of a code, bound to its row so a hash cannot be reused elsewhere."
  def hash_code(code_id, code), do: hmac("code:#{code_id}:" <> code)

  def hash_email(email), do: hmac("email:" <> email)

  def same?(left, right), do: Plug.Crypto.secure_compare(left, right)

  defp hmac(data), do: :crypto.mac(:hmac, :sha256, secret(), data)

  # Derived once (PBKDF2), then read without cost.
  defp secret do
    case :persistent_term.get({__MODULE__, :secret}, nil) do
      nil ->
        base = SyliAtlasWeb.Endpoint.config(:secret_key_base)
        secret = Plug.Crypto.KeyGenerator.generate(base, "syli_atlas accounts hmac", length: 32)
        :persistent_term.put({__MODULE__, :secret}, secret)
        secret

      secret ->
        secret
    end
  end
end
