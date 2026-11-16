defmodule SyliAtlas.Plausible do
  @moduledoc """
  The audience of the site, read from Plausible's Stats API (v2) for the
  administrators' daily email: visitors, visits, pages viewed, time spent,
  the most viewed pages and where visits come from. Dates are the site's
  days in Plausible (Paris time).

  Key: the Railway variable `PLAUSIBLE_API_KEY` (a Stats API key);
  `PLAUSIBLE_SITE_ID` if the site is not `syliatlas.com`. Without a key
  every call answers `{:error, :no_api_key}` and the email says so.
  """
  require Logger

  @url "https://plausible.io/api/v2/query"

  # Sources that are AI assistants, grouped in one line of the email.
  @assistants ~w(ChatGPT chatgpt.com Perplexity perplexity.ai Claude claude.ai Gemini gemini.google.com Copilot copilot.microsoft.com)

  def config, do: Application.get_env(:syli_atlas, __MODULE__, [])
  def configured?, do: config()[:api_key] not in [nil, ""]
  defp site, do: config()[:site_id] || "syliatlas.com"

  @doc """
  The figures of one day: `%{visitors, visits, pageviews, visit_duration}`
  (duration in seconds).
  """
  def day(%Date{} = date) do
    with {:ok, [row | _]} <-
           query(%{
             "metrics" => ~w(visitors visits pageviews visit_duration),
             "date_range" => [Date.to_iso8601(date), Date.to_iso8601(date)]
           }) do
      [visitors, visits, pageviews, duration] = row["metrics"]
      {:ok, %{visitors: visitors, visits: visits, pageviews: pageviews, visit_duration: duration}}
    else
      {:ok, []} -> {:ok, %{visitors: 0, visits: 0, pageviews: 0, visit_duration: 0}}
      other -> other
    end
  end

  @doc "The most viewed pages of a day: `[{path, pageviews}]`."
  def top_pages(%Date{} = date, limit \\ 5) do
    with {:ok, rows} <-
           query(%{
             "metrics" => ["pageviews"],
             "dimensions" => ["event:page"],
             "date_range" => [Date.to_iso8601(date), Date.to_iso8601(date)],
             "order_by" => [["pageviews", "desc"]],
             "pagination" => %{"limit" => limit}
           }) do
      {:ok, for(r <- rows, do: {hd(r["dimensions"]), hd(r["metrics"])})}
    end
  end

  @doc """
  Where the visits of a day come from: `[{source, visits}]`, most first,
  AI assistants grouped as `:assistants`, « Direct / None » as `:direct`.
  """
  def sources(%Date{} = date) do
    with {:ok, rows} <-
           query(%{
             "metrics" => ["visits"],
             "dimensions" => ["visit:source"],
             "date_range" => [Date.to_iso8601(date), Date.to_iso8601(date)],
             "order_by" => [["visits", "desc"]],
             "pagination" => %{"limit" => 50}
           }) do
      grouped =
        rows
        |> Enum.map(fn r -> {group(hd(r["dimensions"])), hd(r["metrics"])} end)
        |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
        |> Enum.map(fn {k, v} -> {k, Enum.sum(v)} end)
        |> Enum.sort_by(&(-elem(&1, 1)))

      {:ok, grouped}
    end
  end

  defp group("Direct / None"), do: :direct
  defp group(source) when source in @assistants, do: :assistants
  defp group(source), do: source

  defp query(body) do
    if configured?() do
      [
        url: @url,
        method: :post,
        json: Map.put(body, "site_id", site()),
        headers: [{"authorization", "Bearer " <> config()[:api_key]}],
        receive_timeout: 20_000,
        retry: :transient
      ]
      |> Keyword.merge(config()[:req_options] || [])
      |> Req.request()
      |> case do
        {:ok, %Req.Response{status: 200, body: %{"results" => rows}}} ->
          {:ok, rows}

        {:ok, %Req.Response{status: status, body: body}} ->
          Logger.error("plausible: HTTP #{status} #{inspect(body) |> String.slice(0, 200)}")
          {:error, {:http, status}}

        {:error, error} ->
          {:error, error}
      end
    else
      {:error, :no_api_key}
    end
  end
end
