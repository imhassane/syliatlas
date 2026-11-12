defmodule SyliAtlas.Workers.BudgetFetchWorker do
  @moduledoc """
  Watches the official pages set in the admin (collection mode `auto`):
  every morning, one job per country reads its page, keeps the links that
  match its pattern (by default, the PDF files), and stores the files not
  read yet. Each new file goes to the AI (`BudgetExtractWorker`).

  Without arguments (the cron), it queues one job per watched country.
  """
  use Oban.Worker,
    queue: :budgets,
    max_attempts: 3,
    unique: [
      keys: [:country_code],
      period: 3600,
      states: [:available, :scheduled, :executing, :retryable]
    ]

  require Logger
  import Ecto.Query
  alias SyliAtlas.{Budgets, Repo}
  alias SyliAtlas.Budgets.Document
  alias SyliAtlas.Workers.BudgetExtractWorker

  # Files read per page and run: the newest links first.
  @per_run 5

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"country_code" => code}}) do
    profile = Budgets.get_profile!(code)

    with "auto" <- profile.collection_mode,
         {:ok, %{status: 200, body: html}} when is_binary(html) <- get(profile.auto_url) do
      links = links(html, profile.auto_url, profile.auto_pattern)

      known =
        MapSet.new(Repo.all(from d in Document, where: d.country_code == ^code, select: d.url))

      new =
        links
        |> Enum.reject(&MapSet.member?(known, &1))
        |> Enum.take(@per_run)

      Enum.each(new, &fetch_file(code, &1))
      :ok
    else
      "manual" -> {:cancel, :not_watched}
      {:ok, %{status: status}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  def perform(%Oban.Job{}) do
    for p <- Budgets.auto_profiles() do
      %{"country_code" => p.country_code} |> new() |> Oban.insert!()
    end

    :ok
  end

  defp fetch_file(code, url) do
    case get(url) do
      {:ok, %{status: 200, body: body} = resp} when is_binary(body) ->
        type = resp |> Req.Response.get_header("content-type") |> List.first() |> content_type()

        case Budgets.store_document(code, "auto", %{
               body: body,
               url: url,
               filename: url |> URI.parse() |> Map.get(:path, "") |> Path.basename(),
               content_type: type
             }) do
          {:ok, document, :new} -> BudgetExtractWorker.enqueue(document)
          {:ok, _document, :duplicate} -> :ok
          {:error, reason} -> Logger.warning("budget fetch #{code} #{url}: #{inspect(reason)}")
        end

      other ->
        Logger.warning("budget fetch #{code} #{url}: #{inspect(other) |> String.slice(0, 200)}")
    end
  end

  defp content_type(nil), do: nil
  defp content_type(v), do: v |> String.split(";") |> hd() |> String.trim() |> String.downcase()

  @doc false
  def links(html, base, pattern) do
    regex = if pattern in [nil, ""], do: ~r/\.pdf($|\?)/i, else: Regex.compile!(pattern, "i")

    ~r/href\s*=\s*["']([^"'#]+)["']/i
    |> Regex.scan(html, capture: :all_but_first)
    |> Enum.map(fn [href] ->
      href |> String.trim() |> then(&URI.merge(base, &1)) |> URI.to_string()
    end)
    |> Enum.filter(&Regex.match?(regex, &1))
    |> Enum.uniq()
  end

  defp get(url) do
    options = Application.get_env(:syli_atlas, __MODULE__, [])

    [url: url, retry: :transient, receive_timeout: 60_000, max_redirects: 5, decode_body: false]
    |> Keyword.merge(Keyword.get(options, :req_options, []))
    |> Req.request()
  end
end
