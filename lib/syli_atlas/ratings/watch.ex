defmodule SyliAtlas.Ratings.Watch do
  @moduledoc """
  The ratings news watch. Reads the headlines of a few African business
  news feeds, keeps the items that look like a sovereign rating decision
  (an agency, a rating word and an African country), reads each article
  and asks `SyliAtlas.Ratings.Extractor` for the decisions it reports.
  Every decision found becomes a proposal in the admin queue; nothing is
  published here.

  Feeds are only leads: titles and texts are not republished, and the
  published source is always the agency's release. Check each feed's terms
  before adding it (config `:feeds`).
  """
  require Logger
  import Ecto.Query

  alias SyliAtlas.Repo
  alias SyliAtlas.Ratings
  alias SyliAtlas.Ratings.{Extractor, Review, Text, WatchItem}

  @default_feeds [
    {"allAfrica · business", "https://allafrica.com/tools/headlines/rdf/business/headlines.rdf"},
    {"Financial Afrik", "https://www.financialafrik.com/feed/"},
    {"The Africa Report", "https://www.theafricareport.com/feed/"}
  ]

  @agency ~r/\b(fitch|moody'?s|s&p|standard (&|and) poor'?s|afcra)\b/
  @topic ~r/\b(rating|ratings|rated|notation|note souveraine|outlook|perspective|upgrade[sd]?|downgrade[sd]?|rehauss|releve|abaiss|degrad|affirm|confirm|default|defaut)/
  @per_run 15
  @max_age_days 10
  @state_key "ratings:watch"

  def config, do: Application.get_env(:syli_atlas, __MODULE__, [])
  def feeds, do: config()[:feeds] || @default_feeds

  @doc "Collects the new items, then extracts the decisions of up to #{@per_run} of them."
  def run do
    countries = countries()
    collected = Enum.sum(for {name, url} <- feeds(), do: collect(name, url, countries))

    result =
      if Extractor.configured?() do
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

  # %{code => "name fr / name en"} of the 54 countries, from the ratings document.
  defp countries do
    case Ratings.document() do
      %{"countries" => countries} ->
        Map.new(countries, fn {code, e} -> {code, "#{e["name"]["en"]} / #{e["name"]["fr"]}"} end)

      _ ->
        %{}
    end
  end

  @doc false
  def relevant?(text, countries) do
    folded = Text.fold(text)

    Regex.match?(@agency, folded) and Regex.match?(@topic, folded) and
      Enum.any?(countries, fn {_code, names} ->
        names
        |> String.split(" / ")
        |> Enum.any?(&String.contains?(folded, Text.fold(&1)))
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
        Logger.warning("ratings watch: feed #{feed} unreadable (#{inspect(reason)})")
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

    case Extractor.extract(item.title, text, countries) do
      {:ok, decisions} ->
        proposals = Enum.count(decisions, &propose(&1, item))
        update!(item, if(decisions == [], do: "ignored", else: "extracted"))
        proposals

      {:error, reason} ->
        update!(item, "failed", inspect(reason))
        0
    end
  end

  defp propose(decision, item) do
    entry = Ratings.for_country(Ratings.document(), decision["country_code"])
    current = entry && Enum.find(entry["agencies"], &(&1["agency"] == decision["agency"]))

    # Already online: same rating and outlook, not newer than the decision shown.
    known? =
      current && current["rating"] == decision["rating"] &&
        current["outlook"] == decision["outlook"] &&
        decision["action_date"] <= (current["action_date"] || "")

    if known? do
      false
    else
      decision
      |> Map.merge(%{
        "origin" => "watch",
        "article_url" => item.url,
        "article_title" => item.title,
        "watch_item_id" => item.id
      })
      |> Review.propose()
      |> then(&match?({:ok, _}, &1))
    end
  end

  defp update!(item, status, error \\ nil),
    do: item |> WatchItem.changeset(%{status: status, error: error}) |> Repo.update!()

  defp summarize(counts), do: %{proposals: Enum.sum(counts), read: length(counts)}

  defp get(url) do
    [
      url: url,
      headers: [{"user-agent", "SyliAtlas/1.0 (ratings watch)"}],
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
