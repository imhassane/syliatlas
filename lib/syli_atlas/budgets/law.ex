defmodule SyliAtlas.Budgets.Law do
  @moduledoc """
  A budget law published on the site, always approved by a human with the
  link to the official text. Amounts are exact decimals in the country's
  currency (`currency`).
  """
  use Ecto.Schema
  alias SyliAtlas.Market.DecimalText

  @kinds ~w(initial amending settlement provisional)
  @stages ~w(tabled voted promulgated published)

  def kinds, do: @kinds
  def stages, do: @stages

  schema "budget_laws" do
    field :country_code, :string
    field :fiscal_year, :integer
    field :kind, :string
    field :sequence, :integer, default: 1
    field :stage, :string
    field :reference, :string
    field :title, :string
    field :legislature, :string
    field :tabled_on, :date
    field :voted_on, :date
    field :promulgated_on, :date
    field :published_on, :date
    field :votes_for, :integer
    field :votes_against, :integer
    field :revenue, DecimalText
    field :expenditure, DecimalText
    field :currency, :string
    field :source_name, :string
    field :source_url, :string
    field :document_id, :integer
    field :approved_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  @doc "The day the law last moved: published, promulgated, voted or tabled."
  def last_date(%{} = law),
    do: law.published_on || law.promulgated_on || law.voted_on || law.tabled_on
end
