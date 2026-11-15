defmodule SyliAtlas.National.Watch do
  @moduledoc """
  The rebasing watch. Reads the headlines of the same African business news
  feeds as the ratings watch, keeps the items that look like a rebasing of
  national accounts (a base-year word, a GDP word and an African country),
  reads each article and asks `SyliAtlas.National.RebasingExtractor` for
  the rebasings it reports. Each becomes a proposal in
  /admin/chiffres-nationaux; nothing is published here.

  Feeds are only leads: the published source is the statistics office's
  release, which the person completes before publishing.
  """
  require Logger
  import Ecto.Query

  alias SyliAtlas.{Geo, Repo}
  alias SyliAtlas.National.{RebasingExtractor, Rebasings, WatchItem}
  alias SyliAtlas.Ratings.Text

  @base ~r/\b(rebas\w*|re-bas\w*|base year|new base|annee de base|nouvelle base|anno base|ano[- ]base|changement d.annee de base)\b/
  @gdp ~r/\b(gdp|pib|national accounts|comptes nationaux|economy|economie)\b/
  @per_run 15
  @max_age_days 20
  @state_key "national:watch"

  def config, do: Application.get_env(:syli_atlas, __MODULE__, [])

  def feeds,
    do: config()[:feeds] || SyliAtlas.Ratings.Watch.feeds()

  @doc "Collects the new items, then extracts the rebasings of up to #{@per_run} of them."
  def run do
    countries = countries()
    collected = Enum.sum(for {name, url} <- feeds(), do: collect(name, url, countries))

    result =
      if RebasingExtractor.configured?() do
        pending_items() |> Enum.map(&process(&1, countries)) |> summarize()
      else
        %{proposals: 0, read: 0}
      end

    record_run!()
    Map.put(result, :collected, collected)
  end

  @doc "When the watch last ran, or nil."
  def last_run do
    case Repo.query!("SELECT json_extract(json(doc), '$.ran_at') FROM snapshots WHERE key = ?1", [
           @state_key
         ]).rows do
      [[iso]] when is_binary(iso) -> iso |> DateTime.from_iso8601() |> elem(1)
      _ -> nil
    end
  end

  defp record_run! do
    now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

    Repo.query!(
      """
      INSERT INTO snapshots (key, doc, inserted_at, updated_at) VALUES (?1, jsonb(?2), ?3, ?3)
      ON CONFLICT(key) DO UPDATE SET doc = excluded.doc, updated_at = excluded.updated_at
      """,
      [@state_key, Jason.encode!(%{ran_at: now}), now]
    )
  end

  # %{code => "English name / nom français"} of the 54 countries.
  defp countries do
    Map.new(Geo.list_countries(), fn a ->
      {a.code, "#{Geo.Area.name(a, "en")} / #{Geo.Area.name(a, "fr")}"}
    end)
  end

  @doc false
  def relevant?(text, countries) do
    folded = Text.fold(text)

    Regex.match?(@base, folded) and Regex.match?(@gdp, folded) and
      Enum.any?(countries, fn {_code, names} ->
        names |> String.split(" / ") |> Enum.any?(&String.contains?(folded, Text.fold(&1)))
      end)
  end

  defp collect(feed, url, countries) do
    case get(url) do
      {:ok, xml} ->
        cutoff = DateTime.add(DateTime.utc_now(), -@max_age_days * 86_400)

        xml
        |> Text.rss_items()
        |> Enum.filter(&(is_nil(&1.published_at) or DateTime.after?(&1.published_at, cutoff)))
        |> Enum.filter(&relevant?(&1.title <> " " <> &1.summary, countries))
        |> Enum.count(fn item ->
          %WatchItem{}
          |> WatchItem.changeset(Map.merge(item, %{feed: feed, status: "new"}))
          |> Repo.insert(on_conflict: :nothing, conflict_target: :url)
          |> case do
            {:ok, %WatchItem{id: id}} when not is_nil(id) -> true
            _ -> false
          end
        end)

      {:error, reason} ->
        Logger.warning("rebasing watch: feed #{feed} unreadable (#{inspect(reason)})")
        0
    end
  end

  defp pending_items do
    Repo.all(
      from i in WatchItem,
        where: i.status == "new",
        order_by: [desc: i.published_at, desc: i.id],
        limit: @per_run
    )
  end

  defp process(item, countries) do
    text =
      case get(item.url) do
        {:ok, html} -> Text.html_to_text(html)
        _ -> ""
      end

    text = if String.length(text) < 200, do: item.summary, else: text

    case RebasingExtractor.extract(item.title, text, countries) do
      {:ok, found} ->
        proposals = Enum.count(found, &propose(&1, item))
        update!(item, if(found == [], do: "ignored", else: "extracted"))
        proposals

      {:error, reason} ->
        update!(item, "failed", inspect(reason))
        0
    end
  end

  defp propose(r, item) do
    announced_on =
      r["announced_on"] ||
        (item.published_at && Date.to_iso8601(DateTime.to_date(item.published_at))) ||
        Date.to_iso8601(Date.utc_today())

    %{
      "country_code" => r["country_code"],
      "announced_on" => announced_on,
      "old_base" => r["old_base"],
      "new_base" => r["new_base"],
      "level_change_pct" => r["level_change_pct"],
      "source_name" => r["institution"] && "#{r["institution"]} (rapporté par #{item.feed})",
      "origin" => "watch",
      "article_url" => item.url,
      "article_title" => item.title,
      "excerpt" => r["excerpt"]
    }
    |> Rebasings.propose()
    |> then(&match?({:ok, _}, &1))
  end

  defp update!(item, status, error \\ nil),
    do: item |> WatchItem.changeset(%{status: status, error: error}) |> Repo.update!()

  defp summarize(counts), do: %{proposals: Enum.sum(counts), read: length(counts)}

  defp get(url) do
    [
      url: url,
      headers: [{"user-agent", "SyliAtlas/1.0 (rebasing watch)"}],
      receive_timeout: 20_000,
      max_redirects: 3,
      retry: :transient,
      max_retries: 1
    ]
    |> Keyword.merge(config()[:req_options] || [])
    |> Req.request()
    |> case do
      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) ->
        {:ok, binary_part(body, 0, min(byte_size(body), 600_000))}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http, status}}

      {:error, error} ->
        {:error, error}
    end
  end
end
