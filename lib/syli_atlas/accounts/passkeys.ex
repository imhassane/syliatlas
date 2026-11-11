defmodule SyliAtlas.Accounts.Passkeys do
  @moduledoc """
  Passkeys (WebAuthn): sign in with the device's own lock (fingerprint,
  face, PIN). The checks are the `wax_` library's (signature, origin,
  relying party, challenge, user presence and verification); here, what
  surrounds them:

    * a challenge per ceremony, kept in the database, used once, 2 minutes;
    * `register/4`: a signed-in account adds one (its public key only). An
      administrator without any passkey may add the first one only right
      after an email code; adding more needs the administration open;
    * `sign_in/2`: a discoverable credential (nothing to type), its counter
      checked against cloning. For an administrator this opens a member
      session: the administration also needs the email code;
    * `confirm/3`: the second proof of an administrator signed in by code;
    * `list/1`, `remove/2`: the last passkey of an administrator stays.
  """
  import Ecto.Query

  alias SyliAtlas.Accounts.{Passkey, Session, Sessions, User, WebauthnChallenge}
  alias SyliAtlas.Repo

  @ttl_seconds 120
  # ES256 and RS256: what phones and computers sign with.
  @algorithms [-7, -257]
  @max_passkeys 10

  @doc "The options of `navigator.credentials.create()`."
  def registration_options(%User{} = user, %Session{} = session, opts \\ []) do
    existing = list(user)

    cond do
      length(existing) >= @max_passkeys ->
        {:error, :too_many_passkeys}

      not may_register?(user, session, existing, now(opts)) ->
        {:error, :admin_proof_required}

      true ->
        challenge = Wax.new_registration_challenge(wax_options(user))
        id = store(challenge, "register", user.id)

        {:ok,
         %{
           challenge_id: id,
           public_key: %{
             challenge: encode(challenge.bytes),
             rp: %{id: challenge.rp_id, name: "Syli Atlas"},
             user: %{
               id: encode(<<user.id::unsigned-64>>),
               name: user.email,
               displayName: user.email
             },
             pubKeyCredParams: Enum.map(@algorithms, &%{type: "public-key", alg: &1}),
             excludeCredentials:
               Enum.map(existing, &%{type: "public-key", id: encode(&1.credential_id)}),
             authenticatorSelection: %{
               residentKey: "required",
               userVerification: user_verification(user)
             },
             attestation: "none",
             timeout: @ttl_seconds * 1000
           }
         }}
    end
  end

  # Members: any session. Administrators: their first passkey right after a
  # code; more passkeys with the administration open.
  defp may_register?(%User{role: "admin"}, session, [], now),
    do: Session.fresh_code?(session, now)

  defp may_register?(%User{role: "admin"}, session, _keys, now),
    do: Session.admin_verified?(session, now)

  defp may_register?(_member, _session, _keys, _now), do: true

  @doc """
  Params: `challenge_id`, `attestation_object`, `client_data_json`
  (base64url), `name`. Registering is also a passkey proof for the session.
  """
  def register(%User{} = user, %Session{} = session, params, opts \\ []) do
    now = now(opts)

    with true <- may_register?(user, session, list(user), now),
         {:ok, challenge} <- consume(params["challenge_id"], "register", user.id),
         {:ok, attestation} <- decode(params["attestation_object"]),
         {:ok, client_data} <- decode(params["client_data_json"]),
         {:ok, {auth_data, _attestation}} <- Wax.register(attestation, client_data, challenge),
         credential = auth_data.attested_credential_data,
         false <- Repo.exists?(where(Passkey, credential_id: ^credential.credential_id)) do
      passkey =
        Repo.insert!(%Passkey{
          user_id: user.id,
          credential_id: credential.credential_id,
          public_key: :erlang.term_to_binary(credential.credential_public_key),
          sign_count: auth_data.sign_count,
          name: name(params["name"]),
          last_used_at: now
        })

      {:ok, passkey, Sessions.record(session, passkey, now: now)}
    else
      _invalid -> {:error, :invalid_passkey}
    end
  end

  @doc "The options of `navigator.credentials.get()`, for any passkey of the site."
  def sign_in_options do
    challenge = Wax.new_authentication_challenge(wax_options(nil))
    id = store(challenge, "sign_in", nil)

    %{
      challenge_id: id,
      public_key: %{
        challenge: encode(challenge.bytes),
        rpId: challenge.rp_id,
        userVerification: "preferred",
        allowCredentials: [],
        timeout: @ttl_seconds * 1000
      }
    }
  end

  @doc """
  Params: `challenge_id`, `credential_id`, `authenticator_data`,
  `client_data_json`, `signature` (base64url). Options: `:now`, `:user_agent`.
  """
  def sign_in(params, opts \\ []) do
    now = now(opts)

    with {:ok, challenge} <- consume(params["challenge_id"], "sign_in", nil),
         {:ok, passkey, user} <- assert(params, challenge, nil, now) do
      {token, session} = Sessions.create(user, passkey, opts)
      {:ok, %{user: user, token: token, session: session}}
    end
  end

  @doc "The options of the administrator's second proof: their own passkeys only."
  def confirm_options(%User{} = user) do
    challenge = Wax.new_authentication_challenge(wax_options(user))
    id = store(challenge, "admin", user.id)

    %{
      challenge_id: id,
      public_key: %{
        challenge: encode(challenge.bytes),
        rpId: challenge.rp_id,
        userVerification: "required",
        allowCredentials:
          Enum.map(list(user), &%{type: "public-key", id: encode(&1.credential_id)}),
        timeout: @ttl_seconds * 1000
      }
    }
  end

  @doc "The administrator's second proof, recorded in the session."
  def confirm(%User{} = user, %Session{} = session, params, opts \\ []) do
    now = now(opts)

    with {:ok, challenge} <- consume(params["challenge_id"], "admin", user.id),
         {:ok, passkey, _user} <- assert(params, challenge, user.id, now) do
      {:ok, passkey, Sessions.record(session, passkey, now: now)}
    end
  end

  defp assert(params, challenge, only_user_id, now) do
    with {:ok, credential_id} <- decode(params["credential_id"]),
         %Passkey{} = passkey <- Repo.get_by(Passkey, credential_id: credential_id),
         true <- only_user_id in [nil, passkey.user_id],
         %User{deactivated_at: nil} = user <- Repo.get(User, passkey.user_id),
         {:ok, auth_data_bin} <- decode(params["authenticator_data"]),
         {:ok, client_data} <- decode(params["client_data_json"]),
         {:ok, signature} <- decode(params["signature"]),
         key = :erlang.binary_to_term(passkey.public_key, [:safe]),
         {:ok, auth_data} <-
           Wax.authenticate(credential_id, auth_data_bin, signature, client_data, challenge, [
             {credential_id, key}
           ]),
         :ok <- check_counter(passkey.sign_count, auth_data.sign_count) do
      passkey =
        passkey
        |> Ecto.Changeset.change(sign_count: auth_data.sign_count, last_used_at: now)
        |> Repo.update!()

      {:ok, passkey, user}
    else
      _invalid -> {:error, :invalid_passkey}
    end
  end

  def list(%User{id: id}),
    do: Passkey |> where(user_id: ^id) |> order_by(:inserted_at) |> Repo.all()

  @doc "Removes a passkey and closes the sessions opened with it."
  def remove(%User{} = user, passkey_id) do
    keys = list(user)

    case Enum.find(keys, &(to_string(&1.id) == to_string(passkey_id))) do
      nil ->
        {:error, :not_found}

      _passkey when user.role == "admin" and length(keys) == 1 ->
        {:error, :last_admin_passkey}

      passkey ->
        Sessions.revoke_by_passkey(passkey.id)
        Repo.delete!(passkey)
        :ok
    end
  end

  # A counter that does not grow means a copied key; synced passkeys keep 0.
  defp check_counter(stored, received) when stored > 0 and received <= stored,
    do: {:error, :cloned}

  defp check_counter(_stored, _received), do: :ok

  defp store(challenge, purpose, user_id) do
    Repo.insert!(%WebauthnChallenge{
      purpose: purpose,
      user_id: user_id,
      challenge: :erlang.term_to_binary(challenge),
      expires_at: DateTime.add(DateTime.utc_now(:second), @ttl_seconds)
    }).id
  end

  # Used once: two submissions of the same challenge cannot both succeed.
  defp consume(id, purpose, user_id) do
    now = DateTime.utc_now(:second)

    with {int, ""} <- Integer.parse(to_string(id)),
         {1, [row]} <-
           Repo.update_all(
             from(c in WebauthnChallenge,
               where:
                 c.id == ^int and c.purpose == ^purpose and is_nil(c.consumed_at) and
                   c.expires_at > ^now,
               where: ^user_condition(user_id),
               select: c
             ),
             set: [consumed_at: now]
           ) do
      {:ok, :erlang.binary_to_term(row.challenge, [:safe])}
    else
      _invalid -> {:error, :invalid_passkey}
    end
  end

  defp user_condition(nil), do: dynamic([c], is_nil(c.user_id))
  defp user_condition(user_id), do: dynamic([c], c.user_id == ^user_id)

  defp name(name) when is_binary(name) and name != "",
    do: name |> String.trim() |> String.slice(0, 60)

  defp name(_none), do: "Passkey"

  defp encode(bytes), do: Base.url_encode64(bytes, padding: false)

  defp decode(value) when is_binary(value) do
    case Base.url_decode64(value, padding: false) do
      {:ok, bytes} -> {:ok, bytes}
      :error -> {:error, :invalid_passkey}
    end
  end

  defp decode(_value), do: {:error, :invalid_passkey}

  # Administrators always verify themselves (fingerprint, face, PIN); a mere touch is not enough.
  defp user_verification(%User{role: "admin"}), do: "required"
  defp user_verification(_user), do: "preferred"

  defp wax_options(user) do
    config = Application.get_env(:syli_atlas, __MODULE__, [])

    [
      origin: Keyword.fetch!(config, :origin),
      rp_id: Keyword.fetch!(config, :rp_id),
      user_verification: if(user, do: user_verification(user), else: "preferred")
    ]
  end

  defp now(opts),
    do: opts |> Keyword.get_lazy(:now, &DateTime.utc_now/0) |> DateTime.truncate(:second)
end
