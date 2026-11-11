defmodule SyliAtlas.Sources.Source do
  @moduledoc "A data provider. The IMF is primary; others only fill gaps."
  use Ecto.Schema
  import Ecto.Changeset

  schema "sources" do
    field :code, :string
    field :name, :string
    field :url, :string
    field :role, :string, default: "primary"
    field :status, :string, default: "active"
    field :last_checked_at, :utc_datetime

    has_many :editions, SyliAtlas.Sources.Edition
    timestamps(type: :utc_datetime)
  end

  def changeset(source, attrs) do
    source
    |> cast(attrs, [:code, :name, :url, :role, :status, :last_checked_at])
    |> validate_required([:code, :name, :url])
    |> validate_inclusion(:role, ~w(primary supplement))
    |> validate_inclusion(:status, ~w(active planned paused))
    |> unique_constraint(:code)
  end
end
