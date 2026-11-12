defmodule SyliAtlas.Market.Pipeline do
  @moduledoc """
  From a stored payload to published values: parse (with the source's
  parser), map to our reference, check, store the observations, then
  consolidate what changed. Runs in one transaction per payload, so a
  payload is either fully taken into account or not at all, and can be
  processed again at any time (for instance after a parser fix).
  """
  require Logger
  import Ecto.Query
  alias SyliAtlas.Repo

  alias SyliAtlas.Market.{
    Consolidation,
    Exchange,
    Ingestion,
    Observation,
    Quality,
    Reference,
    Security,
    Snapshots,
    Source
  }

  @doc "Processes one raw payload. Returns {:ok, summary} or {:error, reason}."
  def process(payload_id) do
    payload = Ingestion.get_payload!(payload_id)
    mod = Source.module(payload.source)
    exchanges = Reference.mappings(payload.source, "exchange")
    ext_of = Map.new(exchanges, fn {ext, id} -> {id, ext} end)

    exchange =
      payload.exchange_code && Repo.get_by(Exchange, code: payload.exchange_code)

    meta = %{exchange: exchange && ext_of[exchange.id]}

    with {:ok, body} <- Ingestion.body(payload),
         {:ok, records} <- mod.parse(payload.dataset, body, meta) do
      result =
        Repo.transaction(fn ->
          ctx = %{
            source: payload.source,
            payload: payload,
            version: mod.parser_version(),
            exchanges: exchanges,
            fallback_date: DateTime.to_date(payload.fetched_at),
            now: DateTime.utc_now() |> DateTime.truncate(:second)
          }

          {summary, touched} =
            Enum.reduce(records, {%{records: 0, stored: 0, skipped: 0}, MapSet.new()}, fn r,
                                                                                          {s, t} ->
              case take(r, ctx) do
                {:stored, key} ->
                  {%{s | records: s.records + 1, stored: s.stored + 1}, MapSet.put(t, key)}

                :skipped ->
                  {%{s | records: s.records + 1, skipped: s.skipped + 1}, t}
              end
            end)

          fx = for %{type: :fx} = r <- records, do: r
          if fx != [], do: Snapshots.put_fx!(fx)

          published =
            Enum.count(touched, fn
              {:index, id, date} -> Consolidation.consolidate_index!(id, date) == :published
              {:security, id, date} -> Consolidation.consolidate_security!(id, date) == :published
            end)

          Ingestion.mark_parsed!(payload, ctx.version)
          Map.put(summary, :published, published)
        end)

      case result do
        {:ok, summary} -> {:ok, summary}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, reason} = error ->
        Ingestion.mark_parsed!(payload, mod.parser_version(), inspect(reason))
        Logger.warning("market payload #{payload_id} not processed: #{inspect(reason)}")
        error
    end
  end

  # Index ------------------------------------------------------------------

  defp take(%{type: :index} = r, ctx) do
    case ctx.exchanges[r.exchange] do
      nil ->
        :skipped

      # A past close never replaces a session already published (which
      # carries its daily change): the history only fills the years before.
      exchange_id when is_map_key(r, :history) and is_map_key(r, :as_of) ->
        if Repo.exists?(
             from v in SyliAtlas.Market.IndexValue,
               where: v.exchange_id == ^exchange_id and v.trade_date == ^trade_date(r, ctx)
           ),
           do: :skipped,
           else: take_index(r, exchange_id, ctx)

      exchange_id ->
        take_index(r, exchange_id, ctx)
    end
  end

  # Security ----------------------------------------------------------------

  defp take(%{type: :security} = r, ctx) do
    with exchange_id when is_integer(exchange_id) <- ctx.exchanges[r.exchange],
         %Security{} = security <- security(r, exchange_id, ctx) do
      date = trade_date(r, ctx)
      {verdict, issues, checked} = Quality.check_security(r)
      Quality.sync!("security", security.id, date, issues, checked)

      if verdict == :reject do
        :skipped
      else
        insert_observation!("security", security.id, date, r, ctx, %{
          close: r.close,
          change: r.change,
          change_pct: r.change_pct,
          volume: r.volume
        })

        {:stored, {:security, security.id, date}}
      end
    else
      _ -> :skipped
    end
  end

  defp take(%{type: :fx}, _ctx), do: :skipped

  # A security known to this source, or created when this source is the
  # exchange's rank 1 for prices. Anything else is reported, never created.
  defp security(r, exchange_id, ctx) do
    ext = r.exchange <> ":" <> r.ticker

    case Reference.resolve(ctx.source, "security", ext) do
      nil ->
        if List.first(Reference.ranked_sources(exchange_id, "prices")) == ctx.source do
          create_security!(r, exchange_id, ext, ctx)
        else
          Logger.info("unknown #{ctx.source} symbol #{ext}: left for reconciliation")
          nil
        end

      id ->
        security = Repo.get!(Security, id)
        refresh_security!(security, r)
    end
  end

  defp create_security!(r, exchange_id, ext, ctx) do
    exchange = Repo.get!(Exchange, exchange_id)
    country = if length(exchange.country_codes) == 1, do: hd(exchange.country_codes)

    security =
      %Security{exchange_id: exchange_id}
      |> Security.changeset(%{
        ticker: r.ticker,
        name: r.name,
        kind: r.kind,
        currency: r.currency || exchange.currency,
        country_code: country,
        issuer: r.issuer,
        isin: r.isin
      })
      |> Repo.insert!(
        on_conflict: {:replace, [:updated_at]},
        conflict_target: [:exchange_id, :ticker],
        returning: true
      )

    Reference.ensure_mapping!(ctx.source, "security", ext, security.id)
    security
  end

  defp refresh_security!(security, r) do
    changes =
      %{name: r.name, issuer: r.issuer || security.issuer, isin: r.isin || security.isin}
      |> Enum.reject(fn {k, v} -> is_nil(v) or Map.get(security, k) == v end)
      |> Map.new()

    if changes == %{},
      do: security,
      else: security |> Ecto.Changeset.change(changes) |> Repo.update!()
  end

  # -------------------------------------------------------------------------

  defp insert_observation!(subject_type, subject_id, date, r, ctx, values) do
    attrs =
      %{
        subject_type: subject_type,
        subject_id: subject_id,
        trade_date: date,
        source: ctx.source,
        currency: Map.get(r, :currency),
        as_of: r.as_of,
        raw_payload_id: ctx.payload.id,
        parser_version: ctx.version,
        ingested_at: ctx.now
      }
      |> Map.merge(
        Map.new(values, fn
          {:volume, v} -> {:volume, v}
          {k, v} -> {k, decimal(v)}
        end)
      )

    struct(Observation, attrs)
    |> Repo.insert!(
      on_conflict: :replace_all,
      conflict_target: [:subject_type, :subject_id, :trade_date, :source, :raw_payload_id]
    )
  end

  defp take_index(r, exchange_id, ctx) do
    case exchange_id do
      nil ->
        :skipped

      exchange_id ->
        date = trade_date(r, ctx)
        {verdict, issues, checked} = Quality.check_index(r)
        checked = if is_nil(r.ytd_pct), do: checked -- ["suspect_change"], else: checked

        # Past closes (index history) are old by nature: never « stale ».
        {issues, checked} =
          if r[:history],
            do: {Enum.reject(issues, &(&1.rule == "stale")), checked -- ["stale"]},
            else: {issues, checked}

        Quality.sync!("index", exchange_id, date, issues, checked)

        if verdict == :reject do
          :skipped
        else
          insert_observation!("index", exchange_id, date, r, ctx, %{
            close: r.value,
            change_pct: r.change_pct,
            ytd_pct: r.ytd_pct
          })

          {:stored, {:index, exchange_id, date}}
        end
    end
  end

  defp trade_date(%{as_of: %DateTime{} = dt}, _ctx), do: DateTime.to_date(dt)
  defp trade_date(_r, ctx), do: ctx.fallback_date

  defp decimal(nil), do: nil
  defp decimal(n) when is_integer(n), do: Decimal.new(n)
  defp decimal(n) when is_float(n), do: Decimal.from_float(n) |> Decimal.normalize()
  defp decimal(%Decimal{} = d), do: d
  defp decimal(s) when is_binary(s), do: Decimal.new(s)

  @doc "Payloads fetched but not parsed yet (after a crash, or a new parser version)."
  def pending_payload_ids do
    Repo.all(
      from p in SyliAtlas.Market.RawPayload,
        where: is_nil(p.parsed_at),
        select: p.id,
        order_by: p.id
    )
  end
end
