defmodule SyliAtlas.Admin.MarketAdmin do
  @moduledoc """
  What the admin « Données de marché » page shows and decides: open
  anomalies with what the reader sees meanwhile, the source published per
  exchange, licences, quota, and the decisions on an anomaly.
  """
  import Ecto.Query
  alias SyliAtlas.Repo
  alias SyliAtlas.Market.{Catalog, Consolidation, Exchange, Ingestion, QualityIssue}
  alias SyliAtlas.Market.{RawPayload, Reference, Security, SourcePriority}
  alias SyliAtlas.Workers.{MarketImportWorker, MarketPublishWorker}

  @doc "Open anomalies with their subject's name, most severe first. Severity filter: high, mid, low."
  def issues(severity \\ nil) do
    query = from(q in QualityIssue, where: q.status == "open")
    query = if severity, do: where(query, [q], q.severity == ^severity), else: query

    issues = Repo.all(query)
    exchanges = Map.new(Reference.list_exchanges(), &{&1.id, &1})

    security_ids = for i <- issues, i.subject_type == "security", do: i.subject_id

    securities =
      Repo.all(from s in Security, where: s.id in ^security_ids)
      |> Map.new(&{&1.id, &1})

    issues
    |> Enum.map(fn i ->
      {where_, exchange_id} =
        case i.subject_type do
          "index" ->
            ex = exchanges[i.subject_id]
            {(ex && ex.short_name) || "?", i.subject_id}

          "security" ->
            s = securities[i.subject_id]
            ex = s && exchanges[s.exchange_id]
            {"#{(s && s.name) || "?"} · #{(ex && ex.short_name) || "?"}", s && s.exchange_id}

          _ ->
            {"—", nil}
        end

      Map.merge(Map.from_struct(i), %{where: where_, exchange_id: exchange_id})
    end)
    |> Enum.sort_by(&{severity_rank(&1.severity), &1.where})
  end

  @doc "Counts of open anomalies: total, by severity, and how many hide a figure."
  def issue_counts do
    rows =
      Repo.all(
        from q in QualityIssue,
          where: q.status == "open",
          group_by: [q.severity, q.rule],
          select: {q.severity, q.rule, count(q.id)}
      )

    by = fn pred -> rows |> Enum.filter(pred) |> Enum.map(&elem(&1, 2)) |> Enum.sum() end

    %{
      all: by.(fn _ -> true end),
      high: by.(&(elem(&1, 0) == "high")),
      mid: by.(&(elem(&1, 0) == "mid")),
      low: by.(&(elem(&1, 0) == "low")),
      hiding: by.(&(elem(&1, 1) in ["abnormal_change", "invalid_price", "index_missing"]))
    }
  end

  @doc """
  Decides on an anomaly:

    * `"accept"` – the data is right as it is: the badge goes away;
    * `"publish"` – a held price is published anyway (abnormal change);
    * `"ignore"` – not worth a badge;
    * `"retry"` – fetch again (catch-up import); the anomaly stays open
      and closes itself if the new data no longer shows it.
  """
  def decide(%QualityIssue{status: "open"} = issue, action)
      when action in ["accept", "publish", "ignore"] do
    status = if action == "ignore", do: "ignored", else: "accepted"
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, issue} =
      issue |> Ecto.Changeset.change(status: status, resolved_at: now) |> Repo.update()

    if action == "publish" and issue.subject_type == "security" and issue.trade_date do
      Consolidation.consolidate_security!(issue.subject_id, issue.trade_date)
    end

    {:ok, _} = MarketPublishWorker.new(%{}) |> Oban.insert()
    {:ok, issue}
  end

  def decide(%QualityIssue{status: "open"}, "retry") do
    {:ok, _} = MarketImportWorker.new(%{"mode" => "catchup"}) |> Oban.insert()
    {:ok, :queued}
  end

  def decide(_issue, _action), do: {:error, :already_decided}

  def get_issue!(id), do: Repo.get!(QualityIssue, id)

  @doc "Each exchange: published source (rank 1), fallback, sources in test, last session, open anomalies."
  def exchanges do
    priorities =
      Repo.all(from p in SourcePriority, order_by: [p.exchange_id, p.rank])
      |> Enum.group_by(& &1.exchange_id)

    last_sessions =
      Repo.all(
        from p in "market_eod_prices",
          join: s in Security,
          on: s.id == p.security_id,
          group_by: s.exchange_id,
          select: {s.exchange_id, max(p.trade_date)}
      )
      |> Map.new()

    issues = issues() |> Enum.frequencies_by(& &1.exchange_id)

    for ex <- Reference.list_exchanges() do
      ranked = (priorities[ex.id] || []) |> Enum.map(& &1.source) |> Enum.uniq()

      planned =
        for s <- Catalog.all(),
            s.status != "active",
            s.code not in ranked,
            serves?(s.code, ex),
            do: s.code

      %{
        exchange: ex,
        rank1: List.first(ranked),
        fallback: Enum.drop(ranked, 1),
        planned: planned,
        last_session: last_sessions[ex.id] && to_date(last_sessions[ex.id]),
        issues: Map.get(issues, ex.id, 0)
      }
    end
  end

  @doc "The last import: when, and how many payloads and exchanges."
  def last_import do
    case Repo.one(
           from p in RawPayload, order_by: [desc: p.fetched_at], limit: 1, select: p.fetched_at
         ) do
      nil ->
        nil

      at ->
        since = DateTime.add(at, -2, :hour)

        %{
          at: at,
          payloads: Repo.aggregate(from(p in RawPayload, where: p.fetched_at > ^since), :count),
          errors:
            Repo.aggregate(
              from(p in RawPayload, where: p.fetched_at > ^since and not is_nil(p.error)),
              :count
            ),
          securities: Repo.aggregate(Security, :count),
          exchanges: Repo.aggregate(Exchange, :count)
        }
    end
  end

  def quota(source \\ "mansa") do
    s = Catalog.get!(source)
    %{calls: Ingestion.calls(source), quota: s.daily_quota, cap: s.daily_cap}
  end

  @doc "How many exchanges publish an official source (rank 1 of kind « official »)."
  def official_count(rows) do
    Enum.count(rows, fn r -> r.rank1 && match?(%{kind: "official"}, Catalog.get(r.rank1)) end)
  end

  @doc "Sources compared without being published (no rank): none until a second parser exists."
  def shadow_sources do
    ranked = Repo.all(from p in SourcePriority, distinct: true, select: p.source)
    for s <- Catalog.all(), s.code not in ranked, do: s
  end

  def market_paused? do
    case Oban.check_queue(queue: :market) do
      %{paused: paused} -> paused
      _ -> false
    end
  rescue
    _ -> false
  catch
    :exit, _ -> false
  end

  defp serves?("brvm_boc", %{code: code}), do: code == "brvm"
  defp serves?("ngx_daily", %{code: code}), do: code == "ngx"
  defp serves?(_source, _ex), do: false

  defp to_date(%Date{} = d), do: d
  defp to_date(s) when is_binary(s), do: Date.from_iso8601!(String.slice(s, 0, 10))

  defp severity_rank("high"), do: 0
  defp severity_rank("mid"), do: 1
  defp severity_rank(_), do: 2
end
