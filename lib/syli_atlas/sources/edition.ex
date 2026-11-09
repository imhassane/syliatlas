defmodule SyliAtlas.Sources.Edition do
  @moduledoc """
  One release of a source, such as the IMF World Economic Outlook of
  October 2026. Editions are kept so that revisions stay visible and an
  import can be rolled back.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending validated published failed superseded)

  schema "editions" do
    field :code, :string
    field :label, :string
    field :status, :string, default: "pending"
    field :fetched_at, :utc_datetime
    field :published_at, :utc_datetime
    field :checksum, :string
    field :stats, :map, default: %{}
    field :warnings, {:array, :string}, default: []

    belongs_to :source, SyliAtlas.Sources.Source
    timestamps(type: :utc_datetime)
  end

  def changeset(edition, attrs) do
    edition
    |> cast(attrs, [
      :source_id,
      :code,
      :label,
      :status,
      :fetched_at,
      :published_at,
      :checksum,
      :stats,
      :warnings
    ])
    |> validate_required([:source_id, :code, :label])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint([:source_id, :code])
  end
end
