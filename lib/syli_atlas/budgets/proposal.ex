defmodule SyliAtlas.Budgets.Proposal do
  @moduledoc """
  A budget law waiting for a human: read from a document by the AI (with the
  page of each figure) or typed in the admin. It becomes a
  `SyliAtlas.Budgets.Law` only once approved with the link to the official
  text.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias SyliAtlas.Budgets.Law
  alias SyliAtlas.Market.DecimalText

  @statuses ~w(pending approved rejected)

  schema "budget_proposals" do
    field :country_code, :string
    belongs_to :document, SyliAtlas.Budgets.Document
    field :origin, :string, default: "manual"
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
    field :evidence, :map, default: %{}
    field :checks, {:array, :map}, default: []
    field :model, :string
    field :status, :string, default: "pending"
    field :reviewed_at, :utc_datetime
    field :law_id, :integer
    timestamps(type: :utc_datetime)
  end

  @fields ~w(country_code document_id origin fiscal_year kind sequence stage reference title
             legislature tabled_on voted_on promulgated_on published_on votes_for votes_against
             revenue expenditure currency source_name source_url evidence model)a

  @doc "The fields of a law, as the admin form and the AI fill them."
  def law_fields,
    do: ~w(fiscal_year kind sequence stage reference title legislature tabled_on voted_on
           promulgated_on published_on votes_for votes_against revenue expenditure currency
           source_name source_url)a

  def changeset(proposal, attrs) do
    proposal
    |> cast(normalize(attrs), @fields, empty_values: [""])
    |> update_change(:country_code, &String.upcase/1)
    |> update_change(:currency, &String.upcase/1)
    |> validate_required([:country_code, :origin])
    |> validate_inclusion(:origin, ~w(extraction manual))
    |> validate_inclusion(:kind, Law.kinds())
    |> validate_inclusion(:stage, Law.stages())
    |> validate_number(:fiscal_year, greater_than_or_equal_to: 2000, less_than_or_equal_to: 2100)
    |> validate_number(:sequence, greater_than_or_equal_to: 1, less_than_or_equal_to: 9)
    |> validate_number(:votes_for, greater_than_or_equal_to: 0)
    |> validate_number(:votes_against, greater_than_or_equal_to: 0)
    |> validate_format(:currency, ~r/^[A-Z]{3}$/)
  end

  @doc """
  What approving needs on top: the year, the kind, the stage, the currency
  and the official source (an https link).
  """
  def approval_changeset(proposal, attrs) do
    proposal
    |> changeset(attrs)
    |> validate_required([:fiscal_year, :kind, :stage, :currency, :source_name, :source_url])
    |> validate_change(:source_url, fn :source_url, url ->
      case URI.parse(url) do
        %URI{scheme: "https", host: host} when is_binary(host) and host != "" -> []
        _ -> [source_url: "must be an https link to the official text"]
      end
    end)
  end

  def review_changeset(proposal, status) when status in @statuses do
    change(proposal,
      status: status,
      reviewed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    )
  end

  # Amounts typed or read as « 3 993 300 000 000 » or « 3.993.300 000,50 »;
  # dates as « 31/03/2026 ».
  defp normalize(attrs) when is_map(attrs) do
    # Only the keys given: a missing key must not clear a field.
    attrs
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
    |> Map.new(fn
      {k, v} when k in ~w(revenue expenditure) -> {k, amount(v)}
      {k, v} when k in ~w(tabled_on voted_on promulgated_on published_on) -> {k, date(v)}
      kv -> kv
    end)
  end

  @doc false
  def amount(nil), do: nil
  def amount(%Decimal{} = d), do: d
  def amount(n) when is_number(n), do: n

  def amount(s) when is_binary(s) do
    s = s |> String.replace(~r/[\s\x{00A0}\x{202F}']/u, "")

    cond do
      s == "" ->
        ""

      # 1.234.567,89 or 1234567,89: the comma is the decimal mark.
      Regex.match?(~r/^\d{1,3}(\.\d{3})+(,\d+)?$/, s) or Regex.match?(~r/^\d+,\d+$/, s) ->
        s |> String.replace(".", "") |> String.replace(",", ".")

      # 1,234,567.89: commas group thousands.
      Regex.match?(~r/^\d{1,3}(,\d{3})+(\.\d+)?$/, s) ->
        String.replace(s, ",", "")

      true ->
        s
    end
  end

  defp date(s) when is_binary(s) do
    case Regex.run(~r/^(\d{1,2})[\/.](\d{1,2})[\/.](\d{4})$/, String.trim(s)) do
      [_, d, m, y] -> "#{y}-#{String.pad_leading(m, 2, "0")}-#{String.pad_leading(d, 2, "0")}"
      nil -> s
    end
  end

  defp date(other), do: other
end
