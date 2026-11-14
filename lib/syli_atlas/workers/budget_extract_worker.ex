defmodule SyliAtlas.Workers.BudgetExtractWorker do
  @moduledoc """
  Reads one budget document with the AI (`SyliAtlas.Budgets.Extractor`) and
  turns each law found into a proposal for the admin queue, checks
  included. One job per document and model: a document is never sent twice
  (and never paid twice) unless an administrator asks again.
  """
  use Oban.Worker,
    queue: :budgets,
    max_attempts: 3,
    unique: [
      keys: [:document_id, :model],
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable, :completed]
    ]

  require Logger
  alias SyliAtlas.Budgets
  alias SyliAtlas.Budgets.Extractor

  @doc "Queues the reading of a document (with the current model)."
  def enqueue(%Budgets.Document{id: id}, opts \\ []) do
    args = %{"document_id" => id, "model" => Extractor.model()}

    # Asked again in the admin: a new job, whatever ran before.
    if Keyword.get(opts, :again) do
      args
      |> Map.put("asked_at", System.system_time(:millisecond))
      |> new(unique: [keys: [:document_id, :model, :asked_at], period: :infinity])
      |> Oban.insert()
    else
      args |> new() |> Oban.insert()
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"document_id" => id}, attempt: attempt, max_attempts: max}) do
    document = Budgets.get_document!(id)
    country = country(document.country_code)

    if Extractor.configured?() do
      Budgets.set_document_status!(document, "extracting")

      result =
        case Budgets.document_body(document) do
          {:ok, body} -> Extractor.extract(body, document.content_type, country)
          {:error, reason} -> {:error, {:raw_store, reason}}
        end

      case result do
        {:ok, laws} ->
          created =
            for %{fields: fields, evidence: evidence} <- laws,
                {:ok, p} <- [
                  Budgets.propose_from_document(document, fields, evidence, Extractor.model())
                ],
                do: p

          Budgets.set_document_status!(
            document,
            "extracted",
            if(laws == [], do: "no budget law found")
          )

          Logger.info(
            "budget extract #{document.country_code} ##{id}: #{length(created)} proposal(s)"
          )

          :ok

        {:error, :too_large} ->
          Budgets.set_document_status!(
            document,
            "failed",
            "file too large for the AI: type the law by hand"
          )

          {:cancel, :too_large}

        {:error, reason} ->
          if attempt >= max, do: Budgets.set_document_status!(document, "failed", inspect(reason))
          {:error, reason}
      end
    else
      Budgets.set_document_status!(document, "no_key")
      {:cancel, :no_api_key}
    end
  end

  defp country(code) do
    area = SyliAtlas.Geo.get_area_by_code(code)

    %{
      code: code,
      name: (area && SyliAtlas.Geo.Area.name(area, "en")) || code,
      currency: (SyliAtlas.Economy.Currencies.for_country(code) || %{})[:code]
    }
  end
end
