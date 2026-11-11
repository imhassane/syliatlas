defmodule SyliAtlas.Market.Snapshots do
  @moduledoc """
  The documents the market pages read, rebuilt after every import: one for
  the list of exchanges (`market:overview`), one per exchange
  (`market:exchange:<code>`), one for the funds (`market:etfs`) and the
  exchange rates (`market:fx`). A page reads one row; the consolidated
  tables are only read here.

  Prices travel as strings ("25500.00"): exact, formatted by the pages.
  """
  import Ecto.Query
  alias SyliAtlas.Repo

  alias SyliAtlas.Market.{
    Catalog,
    EodPrice,
    Exchange,
    IndexValue,
    QualityIssue,
    Reference,
    Security
  }

  @format 2
  @history 260

  def format, do: @format

  @doc "Rebuilds every market document. Returns the number written."
  def rebuild! do
    now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    exchanges = Reference.list_exchanges()
    issues = open_issues()
    areas = Map.new(SyliAtlas.Geo.list_areas(), &{&1.code, &1})
    docs = Enum.map(exchanges, &exchange_doc(&1, issues, areas))

    Repo.transaction(fn ->
      for doc <- docs, do: put!("market:exchange:" <> doc["exchange"]["code"], doc, now)
      put!("market:overview", overview_doc(docs), now)
      put!("market:etfs", etfs_doc(docs), now)
    end)

    SyliAtlas.Market.refresh_data_version()
    length(docs) + 2
  end

  @doc "Stores the latest exchange rates (from a source's forex dataset)."
  def put_fx!(records) do
    rates =
      for r <- records, into: %{}, do: {r.pair, r.rate}

    as_of =
      records
      |> Enum.map(& &1.as_of)
      |> Enum.reject(&is_nil/1)
      |> Enum.max(DateTime, fn -> nil end)

    put!(
      "market:fx",
      %{"format" => @format, "rates" => rates, "as_of" => as_of && DateTime.to_iso8601(as_of)},
      DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    )
  end

  def read(key) do
    case Repo.query!("SELECT json(doc) FROM snapshots WHERE key = ?1", [key]).rows do
      [[json]] when is_binary(json) -> Jason.decode!(json)
      _ -> nil
    end
  end

  defp put!(key, doc, now) do
    Repo.query!(
      """
      INSERT INTO snapshots (key, doc, inserted_at, updated_at) VALUES (?1, jsonb(?2), ?3, ?3)
      ON CONFLICT(key) DO UPDATE SET doc = excluded.doc, updated_at = excluded.updated_at
      """,
      [key, Jason.encode!(doc), now]
    )
  end

  # One exchange --------------------------------------------------------------

  defp exchange_doc(%Exchange{} = e, issues, areas) do
    history =
      Repo.all(
        from v in IndexValue,
          where: v.exchange_id == ^e.id,
          order_by: [desc: v.trade_date],
          limit: @history
      )

    latest_index = List.first(history)

    securities =
      Repo.all(from s in Security, where: s.exchange_id == ^e.id)

    latest_prices = latest_prices(Enum.map(securities, & &1.id))
    session_date = latest_prices |> Map.values() |> Enum.map(& &1.trade_date) |> max_date()

    rows =
      securities
      |> Enum.map(fn s -> security_row(s, latest_prices[s.id], session_date, issues) end)
      |> Enum.sort_by(&{-(&1["value"] || -1.0), &1["ticker"]})

    session_rows = Enum.filter(rows, &(&1["trade_date"] == date(session_date)))
    traded = Enum.filter(session_rows, &((&1["volume"] || 0) > 0))
    total_value = traded |> Enum.map(&(&1["value"] || 0.0)) |> Enum.sum()

    index_issues = Map.get(issues, {"index", e.id}, [])

    %{
      "format" => @format,
      "exchange" => exchange_fields(e, length(securities), areas),
      "index" => index_fields(latest_index, index_issues),
      "history" => history |> Enum.reverse() |> Enum.map(&[date(&1.trade_date), str(&1.value)]),
      "session" => %{
        "date" => date(session_date),
        "up" => Enum.count(session_rows, &positive?(&1["change_pct"])),
        "down" => Enum.count(session_rows, &negative?(&1["change_pct"])),
        "flat" => Enum.count(session_rows, &zero?(&1["change_pct"])),
        "none" => Enum.count(session_rows, &is_nil(&1["change_pct"])),
        "value" => round_value(total_value),
        "top" => top_share(traded, total_value)
      },
      "securities" => rows,
      "movers_up" =>
        traded
        |> Enum.filter(&positive?(&1["change_pct"]))
        |> Enum.sort_by(&(-to_f(&1["change_pct"])))
        |> Enum.take(5),
      "movers_down" =>
        traded
        |> Enum.filter(&negative?(&1["change_pct"]))
        |> Enum.sort_by(&to_f(&1["change_pct"]))
        |> Enum.take(5),
      "issues" => Enum.map(index_issues, &issue_fields/1),
      "sources" => sources(e)
    }
  end

  defp exchange_fields(e, listed, areas) do
    countries =
      for code <- e.country_codes, a = areas[code], a != nil do
        %{
          "code" => code,
          "name" => %{"fr" => a.name_fr, "en" => a.name_en},
          "slug" => %{"fr" => a.slug_fr, "en" => a.slug_en}
        }
      end

    search =
      [e.short_name, e.name, e.currency, e.index_name, e.mic, e.code]
      |> Enum.concat(Enum.flat_map(countries, &[&1["name"]["fr"], &1["name"]["en"]]))
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")
      |> SyliAtlas.Geo.Area.normalize()

    %{
      "country_names" => countries,
      "search" => search,
      "code" => e.code,
      "mic" => e.mic,
      "short_name" => e.short_name,
      "name" => e.name,
      "currency" => e.currency,
      "region" => e.region_code,
      "countries" => e.country_codes,
      "index_name" => e.index_name,
      "listed" => listed,
      "position" => e.position
    }
  end

  defp index_fields(nil, issues) do
    %{
      "value" => nil,
      "change_pct" => nil,
      "ytd_pct" => nil,
      "date" => nil,
      "source" => nil,
      "flags" => flags(issues)
    }
  end

  defp index_fields(%IndexValue{} = v, issues) do
    %{
      "value" => str(v.value),
      "change_pct" => str(v.change_pct),
      "ytd_pct" => str(v.ytd_pct),
      "date" => date(v.trade_date),
      "source" => v.source,
      "flags" => flags(issues)
    }
  end

  defp flags(issues) do
    rules = MapSet.new(issues, & &1.rule)

    %{
      "missing" => MapSet.member?(rules, "index_missing"),
      "stale" => MapSet.member?(rules, "stale"),
      "suspect" => MapSet.member?(rules, "suspect_change"),
      "stale_since" => Enum.find_value(issues, fn i -> i.rule == "stale" && i.data["as_of"] end)
    }
  end

  defp security_row(%Security{} = s, price, session_date, issues) do
    rules = issues |> Map.get({"security", s.id}, []) |> MapSet.new(& &1.rule)
    close = price && to_f(price.close)
    value = if price && price.volume && close, do: close * price.volume, else: nil

    %{
      "id" => s.id,
      "ticker" => s.ticker,
      "name" => s.name,
      "kind" => s.kind,
      "issuer" => s.issuer,
      "isin" => s.isin,
      "country" => s.country_code,
      "currency" => s.currency,
      "close" => price && str(price.close),
      "change" => price && str(price.change),
      "change_pct" => price && str(price.change_pct),
      "volume" => price && price.volume,
      "value" => round_value(value),
      "trade_date" => price && date(price.trade_date),
      "source" => price && price.source,
      "current" => price != nil and price.trade_date == session_date,
      "flags" => %{
        "no_trade" => MapSet.member?(rules, "no_trade"),
        "stale" => MapSet.member?(rules, "stale"),
        "held" => MapSet.member?(rules, "abnormal_change")
      }
    }
  end

  defp top_share([], _total), do: nil

  defp top_share(traded, total) when total > 0 do
    top = Enum.max_by(traded, &(&1["value"] || 0.0))

    %{
      "ticker" => top["ticker"],
      "name" => top["name"],
      "share" => Float.round((top["value"] || 0.0) / total * 100, 1)
    }
  end

  defp top_share(_traded, _total), do: nil

  defp sources(e) do
    for {code, rank} <- e.id |> Reference.ranked_sources("prices") |> Enum.with_index(1) do
      c = Catalog.get(code) || %{kind: "other"}

      %{
        "code" => code,
        "name" => Catalog.name(code),
        "url" => Catalog.url(code),
        "kind" => c.kind,
        "rank" => rank
      }
    end
  end

  # The latest close of each security, in one query.
  defp latest_prices([]), do: %{}

  defp latest_prices(ids) do
    latest =
      from p in EodPrice,
        where: p.security_id in ^ids,
        group_by: p.security_id,
        select: %{security_id: p.security_id, trade_date: max(p.trade_date)}

    Repo.all(
      from p in EodPrice,
        join: l in subquery(latest),
        on: l.security_id == p.security_id and l.trade_date == p.trade_date
    )
    |> Map.new(&{&1.security_id, &1})
  end

  # All exchanges -------------------------------------------------------------

  defp overview_doc(docs) do
    exchanges =
      for d <- docs do
        %{
          "exchange" => d["exchange"],
          "index" => d["index"],
          "session" => Map.take(d["session"], ~w(date up down flat none value)),
          "sources" => d["sources"],
          "top" =>
            d["securities"]
            |> Enum.filter(
              &(&1["current"] and (&1["volume"] || 0) > 0 and &1["kind"] == "equity")
            )
            |> Enum.take(5)
            |> Enum.map(&Map.take(&1, ~w(ticker name country close change_pct value currency)))
        }
      end

    with_index = Enum.filter(exchanges, &(&1["index"]["change_pct"] != nil))

    %{
      "format" => @format,
      "as_of" =>
        exchanges
        |> Enum.map(& &1["index"]["date"])
        |> Enum.reject(&is_nil/1)
        |> Enum.max(fn -> nil end),
      "exchanges" => exchanges,
      "totals" => %{
        "exchanges" => length(exchanges),
        "securities" => exchanges |> Enum.map(& &1["exchange"]["listed"]) |> Enum.sum(),
        "up" => Enum.count(with_index, &positive?(&1["index"]["change_pct"])),
        "down" => Enum.count(with_index, &negative?(&1["index"]["change_pct"])),
        "flat" => Enum.count(with_index, &zero?(&1["index"]["change_pct"])),
        "none" => length(exchanges) - length(with_index),
        "current" =>
          Enum.count(exchanges, fn x ->
            x["index"]["value"] != nil and not x["index"]["flags"]["stale"]
          end),
        "missing" => Enum.count(exchanges, & &1["index"]["flags"]["missing"]),
        "stale" => Enum.count(exchanges, & &1["index"]["flags"]["stale"])
      },
      "sources" => docs |> Enum.flat_map(& &1["sources"]) |> Enum.uniq_by(& &1["code"])
    }
  end

  defp etfs_doc(docs) do
    rows =
      for d <- docs, s <- d["securities"], s["kind"] == "etf" do
        Map.put(s, "exchange", Map.take(d["exchange"], ~w(code short_name currency)))
      end
      |> Enum.sort_by(&{-(&1["value"] || -1.0), &1["ticker"]})

    %{
      "format" => @format,
      "etfs" => rows,
      "date" =>
        rows |> Enum.map(& &1["trade_date"]) |> Enum.reject(&is_nil/1) |> Enum.max(fn -> nil end),
      "value" => rows |> Enum.map(&(&1["value"] || 0.0)) |> Enum.sum() |> round_value(),
      "sources" =>
        docs
        |> Enum.filter(fn d -> Enum.any?(d["securities"], &(&1["kind"] == "etf")) end)
        |> Enum.flat_map(& &1["sources"])
        |> Enum.uniq_by(& &1["code"])
    }
  end

  defp open_issues do
    Repo.all(from q in QualityIssue, where: q.status == "open")
    |> Enum.group_by(&{&1.subject_type, &1.subject_id})
  end

  defp issue_fields(i),
    do: %{"rule" => i.rule, "severity" => i.severity, "detail" => i.detail, "data" => i.data}

  # Helpers ---------------------------------------------------------------------

  defp max_date([]), do: nil
  defp max_date(dates), do: Enum.max(dates, Date)

  defp date(nil), do: nil
  defp date(%Date{} = d), do: Date.to_iso8601(d)

  defp str(nil), do: nil
  defp str(%Decimal{} = d), do: Decimal.to_string(d, :normal)

  defp to_f(nil), do: nil
  defp to_f(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_f(s) when is_binary(s), do: s |> Decimal.new() |> Decimal.to_float()
  defp to_f(n) when is_number(n), do: n * 1.0

  defp positive?(v), do: is_binary(v) and to_f(v) > 0
  defp negative?(v), do: is_binary(v) and to_f(v) < 0
  defp zero?(v), do: is_binary(v) and to_f(v) == 0

  defp round_value(nil), do: nil
  defp round_value(v), do: Float.round(v * 1.0, 2)
end
