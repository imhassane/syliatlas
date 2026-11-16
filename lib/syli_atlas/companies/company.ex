defmodule SyliAtlas.Companies.Company do
  @moduledoc """
  A company or mine shown on a product page (SyliAtlas.Companies): its
  name, country, kind and owners as its source states them, and the state
  of its last check.

  Statuses: `pending` (never checked), `published` (confirmed by its
  source, word for word, less than 90 days ago), `hidden` (the last check
  did not confirm it: shown nowhere until a check confirms it again),
  `withdrawn` (removed by an administrator: never checked again).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(mine producer state_company holding refinery)
  @statuses ~w(pending published hidden withdrawn)

  schema "companies" do
    field :product, :string
    field :country, :string
    field :name, :string
    field :kind, :string
    field :owners, :string
    field :listing, :string
    field :market_href, :string
    field :source_url, :string
    field :source_name, :string
    field :status, :string, default: "pending"
    field :excerpt, :string
    field :note, :string
    field :checked_at, :utc_datetime
    field :verified_at, :utc_datetime
    field :position, :integer, default: 0
    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds
  def statuses, do: @statuses

  @doc "What an administrator or the seed file may set."
  def changeset(company, attrs) do
    company
    |> cast(attrs, [
      :product,
      :country,
      :name,
      :kind,
      :owners,
      :listing,
      :market_href,
      :source_url,
      :source_name,
      :position
    ])
    |> validate_required([:product, :country, :name, :kind, :source_url, :source_name])
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:product, SyliAtlas.AfricaTrade.products())
    |> validate_format(:country, ~r/^[A-Z]{3}$/)
    |> validate_format(:source_url, ~r{^https://}, message: "must start with https://")
    |> validate_length(:name, max: 120)
    |> validate_length(:owners, max: 200)
    |> unique_constraint([:product, :name])
  end

  @doc "The result of a check, set by SyliAtlas.Companies only."
  def check_changeset(company, attrs) do
    company
    |> cast(attrs, [:status, :excerpt, :note, :checked_at, :verified_at])
    |> validate_inclusion(:status, @statuses)
  end
end
