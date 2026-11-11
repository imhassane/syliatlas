defmodule SyliAtlas.Ratings.Rating do
  @moduledoc """
  One decision of a credit rating agency on a country: its long-term
  foreign-currency rating, the outlook and the date. The latest decision
  of an agency is its current rating.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias SyliAtlas.Ratings.Scale

  @agencies ~w(sp moodys fitch afcra)
  @outlooks ~w(positive negative stable developing none)

  def agencies, do: @agencies

  schema "sovereign_ratings" do
    field :country_code, :string
    field :agency, :string
    field :rating, :string
    field :outlook, :string
    field :action_date, :string, default: ""
    field :action_type, :string
    field :needs_check, :boolean, default: false
    field :source_url, :string
    field :note, :string
    field :reviewed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(rating, attrs) do
    rating
    |> cast(attrs, [
      :country_code,
      :agency,
      :rating,
      :outlook,
      :action_date,
      :action_type,
      :needs_check,
      :source_url,
      :note,
      :reviewed_at
    ])
    |> update_change(:rating, &Scale.normalize/1)
    # An unknown date is stored as "", not NULL (part of the unique key).
    |> then(&if(get_field(&1, :action_date), do: &1, else: force_change(&1, :action_date, "")))
    |> validate_required([:country_code, :agency, :rating])
    |> validate_inclusion(:agency, @agencies)
    |> validate_inclusion(:outlook, @outlooks)
    |> validate_format(:action_date, ~r/^(\d{4}(-\d{2}(-\d{2})?)?)?$/)
    |> validate_change(:rating, fn :rating, value ->
      if Scale.score(value), do: [], else: [rating: "is not a known rating"]
    end)
    |> unique_constraint([:country_code, :agency, :action_date])
  end
end
