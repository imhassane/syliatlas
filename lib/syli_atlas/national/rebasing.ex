defmodule SyliAtlas.National.Rebasing do
  @moduledoc "A change of base year of a country's national accounts, with its source."
  use Ecto.Schema
  import Ecto.Changeset

  schema "national_rebasings" do
    field :country_code, :string
    field :announced_on, :string
    field :old_base, :string
    field :new_base, :string
    field :level_change_pct, :string
    field :source_name, :string
    field :source_url, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(rebasing, attrs) do
    rebasing
    |> cast(attrs, ~w(country_code announced_on old_base new_base level_change_pct
                      source_name source_url)a)
    |> validate_required(~w(country_code announced_on old_base new_base source_name source_url)a)
    |> validate_format(:announced_on, ~r/^\d{4}-\d{2}-\d{2}$/)
    |> validate_format(:source_url, ~r{^https://})
    |> unique_constraint([:country_code, :announced_on])
  end
end
