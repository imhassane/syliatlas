defmodule SyliAtlas.National.Rebasing do
  @moduledoc """
  A change of base year of a country's national accounts, with its source.

  `proposed` by the news watch (or typed in the admin), `published` once a
  person confirms it, `rejected` otherwise. A published rebasing shows an
  alert on the country's pages until an IMF edition takes it in
  (`integrated_edition`).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(proposed published rejected)

  schema "national_rebasings" do
    field :country_code, :string
    field :announced_on, :string
    field :old_base, :string
    field :new_base, :string
    field :level_change_pct, :string
    field :source_name, :string
    field :source_url, :string
    field :status, :string, default: "published"
    field :reference_year, :integer
    field :imf_before, :string
    field :imf_edition, :string
    field :integrated_edition, :string
    field :integrated_on, :string
    field :origin, :string, default: "manual"
    field :article_url, :string
    field :article_title, :string
    field :excerpt, :string
    field :reviewed_by, :string
    field :reviewed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @fields ~w(country_code announced_on old_base new_base level_change_pct source_name
             source_url status reference_year imf_before imf_edition integrated_edition
             integrated_on origin article_url article_title excerpt reviewed_by reviewed_at)a

  def statuses, do: @statuses

  @doc "A rebasing ready to be shown: every field a reader needs."
  def changeset(rebasing, attrs) do
    rebasing
    |> base(attrs)
    |> validate_required(~w(old_base source_name source_url)a)
  end

  @doc "A proposal of the watch: the article is enough, a person completes the rest."
  def proposal_changeset(rebasing, attrs) do
    rebasing
    |> base(attrs)
    |> put_change(:status, "proposed")
  end

  defp base(rebasing, attrs) do
    rebasing
    |> cast(attrs, @fields, empty_values: [""])
    |> update_change(:level_change_pct, &normalize_pct/1)
    |> validate_required(~w(country_code announced_on new_base status)a)
    |> validate_inclusion(:status, @statuses)
    |> validate_format(:country_code, ~r/^[A-Z]{3}$/)
    |> validate_format(:announced_on, ~r/^\d{4}-\d{2}-\d{2}$/)
    |> validate_format(:level_change_pct, ~r/^-?\d+(\.\d+)?$/)
    |> validate_format(:source_url, ~r{^https://})
    |> validate_format(:article_url, ~r{^https?://})
    |> validate_number(:reference_year,
      greater_than_or_equal_to: 2000,
      less_than_or_equal_to: 2035
    )
    |> update_change(:article_title, &String.slice(&1, 0, 250))
    |> update_change(:excerpt, &String.slice(&1, 0, 2000))
    |> unique_constraint([:country_code, :announced_on])
  end

  # « +59,3 % » or « 59.3 » → "59.3".
  defp normalize_pct(nil), do: nil

  defp normalize_pct(v) do
    v
    |> to_string()
    |> String.replace(~r/[%\s+]/u, "")
    |> String.replace(",", ".")
  end
end
