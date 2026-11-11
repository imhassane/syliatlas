defmodule SyliAtlas.Accounts.WebauthnChallenge do
  @moduledoc "A WebAuthn challenge handed to a browser: used once, within 2 minutes."
  use Ecto.Schema

  schema "webauthn_challenges" do
    field :purpose, :string
    field :user_id, :id
    field :challenge, :binary
    field :expires_at, :utc_datetime
    field :consumed_at, :utc_datetime

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
