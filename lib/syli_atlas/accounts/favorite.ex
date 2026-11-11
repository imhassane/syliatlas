defmodule SyliAtlas.Accounts.Favorite do
  @moduledoc """
  Something a member follows: an area (country or region, by code), an
  exchange (by code), a security ("BRVM/SNTS") or a comparison (its slugs).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(area exchange security comparison)

  schema "favorites" do
    belongs_to :user, SyliAtlas.Accounts.User
    field :kind, :string
    field :ref, :string

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def kinds, do: @kinds

  def changeset(user_id, kind, ref) do
    %__MODULE__{user_id: user_id}
    |> change(kind: kind, ref: ref)
    |> validate_required([:kind, :ref])
    |> validate_inclusion(:kind, @kinds)
    |> validate_length(:ref, max: 200)
    |> validate_format(:ref, ~r{^[A-Za-z0-9_./-]+$})
    |> unique_constraint([:user_id, :kind, :ref])
  end
end
