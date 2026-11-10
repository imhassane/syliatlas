defmodule SyliAtlas.Ratings.Proposal do
  @moduledoc """
  A rating decision waiting for a human: proposed by the news watch (AI
  extraction, with the excerpt it relies on) or typed in the admin. It
  becomes a `SyliAtlas.Ratings.Rating` only once approved with the link to
  the agency's own release.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias SyliAtlas.Ratings.{Rating, Scale}

  @statuses ~w(pending approved rejected)
  @outlooks ~w(positive negative stable developing none)
  @action_types ~w(upgrade downgrade affirmed outlook_up outlook_down outlook default)

  def action_types, do: @action_types

  schema "rating_proposals" do
    field :country_code, :string
    field :agency, :string
    field :rating, :string
    field :outlook, :string
    field :action_date, :string, default: ""
    field :action_type, :string
    field :source_url, :string
    field :article_url, :string
    field :article_title, :string
    field :excerpt, :string
    field :origin, :string, default: "manual"
    field :warnings, {:array, :string}, default: []
    field :status, :string, default: "pending"
    field :reviewed_at, :utc_datetime
    belongs_to :watch_item, SyliAtlas.Ratings.WatchItem

    timestamps(type: :utc_datetime)
  end

  @fields [
    :country_code,
    :agency,
    :rating,
    :outlook,
    :action_date,
    :action_type,
    :source_url,
    :article_url,
    :article_title,
    :excerpt,
    :origin,
    :warnings,
    :watch_item_id
  ]

  def changeset(proposal, attrs) do
    proposal
    |> cast(attrs, @fields)
    |> update_change(:rating, &Scale.normalize/1)
    # An unknown date is stored as "", not NULL (part of the unique key).
    |> then(&if(get_field(&1, :action_date), do: &1, else: force_change(&1, :action_date, "")))
    |> update_change(:country_code, &String.upcase/1)
    |> validate_required([:country_code, :agency, :rating])
    |> validate_inclusion(:agency, Rating.agencies())
    |> validate_inclusion(:outlook, @outlooks)
    |> validate_inclusion(:action_type, @action_types)
    |> validate_inclusion(:origin, ~w(watch manual))
    |> validate_format(:action_date, ~r/^(\d{4}(-\d{2}(-\d{2})?)?)?$/)
    |> validate_change(:rating, fn :rating, value ->
      if Scale.score(value), do: [], else: [rating: "is not a known rating"]
    end)
    # SQLite names the violated partial index by its columns.
    |> unique_constraint([:country_code, :agency, :action_date, :rating])
  end

  def review_changeset(proposal, status) when status in @statuses do
    change(proposal,
      status: status,
      reviewed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    )
  end
end
