defmodule SyliAtlas.Accounts.Passkey do
  @moduledoc "A passkey of an account: its credential id, public key and counter."
  use Ecto.Schema

  schema "passkeys" do
    belongs_to :user, SyliAtlas.Accounts.User
    field :credential_id, :binary
    field :public_key, :binary
    field :sign_count, :integer, default: 0
    field :name, :string
    field :last_used_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end
