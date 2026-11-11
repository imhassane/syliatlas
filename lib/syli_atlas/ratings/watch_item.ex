defmodule SyliAtlas.Ratings.WatchItem do
  @moduledoc "A news item read by the ratings watch, kept so it is read only once."
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(new extracted ignored failed)

  schema "rating_watch_items" do
    field :url, :string
    field :title, :string
    field :summary, :string, default: ""
    field :feed, :string, default: ""
    field :published_at, :utc_datetime
    field :status, :string, default: "new"
    field :error, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [:url, :title, :summary, :feed, :published_at, :status, :error])
    |> validate_required([:url, :title])
    |> validate_inclusion(:status, @statuses)
    |> update_change(:title, &String.slice(&1, 0, 250))
    |> update_change(:error, &String.slice(&1, 0, 250))
    |> unique_constraint(:url)
  end
end
