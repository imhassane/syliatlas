defmodule SyliAtlas.SoftAuthenticator do
  @moduledoc """
  A passkey for tests, as a phone makes one: a P-256 key, an attestation in
  the `none` format, and assertions signed over the authenticator data and
  the client data's hash. The server's real checks (`wax_`) run on it.
  """

  defstruct [:credential_id, :public, :private, sign_count: 0]

  @origin "https://syliatlas.test"

  def new do
    {public, private} = :crypto.generate_key(:ecdh, :secp256r1)
    %__MODULE__{credential_id: :crypto.strong_rand_bytes(16), public: public, private: private}
  end

  @doc "The answer of `navigator.credentials.create()` (base64url). Flags: user present and verified."
  def attestation(%__MODULE__{} = key, options, name \\ "Mon téléphone") do
    options = stringify(options)
    client_data = client_data("webauthn.create", options["public_key"]["challenge"])
    <<4, x::binary-32, y::binary-32>> = key.public
    cose = %{1 => 2, 3 => -7, -1 => 1, -2 => bytes(x), -3 => bytes(y)}

    auth_data =
      rp_hash(options["public_key"]["rp"]["id"]) <>
        <<0x45, 0::32>> <>
        <<0::128, byte_size(key.credential_id)::16>> <> key.credential_id <> CBOR.encode(cose)

    attestation_object =
      CBOR.encode(%{"fmt" => "none", "attStmt" => %{}, "authData" => bytes(auth_data)})

    %{
      "challenge_id" => options["challenge_id"],
      "attestation_object" => encode(attestation_object),
      "client_data_json" => encode(client_data),
      "name" => name
    }
  end

  @doc "The answer of `navigator.credentials.get()`, its counter `sign_count`."
  def assertion(%__MODULE__{} = key, options, sign_count \\ 0) do
    options = stringify(options)
    client_data = client_data("webauthn.get", options["public_key"]["challenge"])
    auth_data = rp_hash(options["public_key"]["rpId"]) <> <<0x05, sign_count::32>>

    signature =
      :crypto.sign(:ecdsa, :sha256, auth_data <> :crypto.hash(:sha256, client_data), [
        key.private,
        :secp256r1
      ])

    %{
      "challenge_id" => options["challenge_id"],
      "credential_id" => encode(key.credential_id),
      "authenticator_data" => encode(auth_data),
      "client_data_json" => encode(client_data),
      "signature" => encode(signature)
    }
  end

  # Options straight from the context have atom keys; from JSON, strings.
  defp stringify(options), do: options |> Jason.encode!() |> Jason.decode!()

  defp client_data(type, challenge),
    do: Jason.encode!(%{type: type, challenge: challenge, origin: @origin, crossOrigin: false})

  defp rp_hash(rp_id), do: :crypto.hash(:sha256, rp_id)
  defp bytes(binary), do: %CBOR.Tag{tag: :bytes, value: binary}
  defp encode(bytes), do: Base.url_encode64(bytes, padding: false)
end
