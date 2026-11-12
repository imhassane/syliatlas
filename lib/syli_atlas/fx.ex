defmodule SyliAtlas.Fx do
  @moduledoc """
  Exchange rates of the 42 African currencies, the euro and the yuan
  against the US dollar, kept by Syli Atlas itself (docs/forex.md).

    * Every day `SyliAtlas.Workers.FxImportWorker` fetches the primary
      source (`Sources.ExchangeApi`, CC0) and a check source
      (`Sources.ErApi`, never shown); both responses stay raw.
    * Rates are stored per currency, day and source (`fx_rates`), units of
      the currency per US dollar, as exact decimals.
    * Fixed pegs (CFA francs, Comorian franc, escudo, dobra, loti, Namibian
      dollar, lilangeni, Djibouti franc, nakfa) are never taken from a
      source: they are computed from their anchor and the official parity.
    * `publish!/0` writes one document (`market:fx_rates`) that pages read:
      the latest rates, those of a year earlier and the checks.

  Rates are official ones, as published by the sources; parallel markets
  are not followed. Rates are not handed out by the public API.
  """
  import Ecto.Query
  require Logger

  alias SyliAtlas.Repo
  alias SyliAtlas.Economy.Currencies
  alias SyliAtlas.Fx.Rate
  alias SyliAtlas.Fx.Sources.{ErApi, ExchangeApi}
  alias SyliAtlas.Market.{Ingestion, Snapshots}

  @snapshot "market:fx_rates"
  @extra ~w(EUR CNY)
  @format 1

  @doc "The primary source module."
  def primary, do: ExchangeApi
  @doc "The source that only checks the primary one."
  def shadow, do: ErApi

  @doc "The African currencies, then the euro and the yuan (44 codes)."
  def tracked, do: Currencies.codes() ++ @extra

  # Import ---------------------------------------------------------------

  @doc """
  Fetches one day (`Date` or `:latest`) from a source, keeps the response
  raw, then stores the rates of the tracked currencies.
  Returns `{:ok, day, count}` or `{:error, reason}`.
  """
  def import(source, day \\ :latest) do
    with {:ok, response} <- source.fetch(day, []),
         payload = Ingestion.store!(source.code(), "fx", nil, response),
         {:parse, {:ok, date, rates}, _payload} <- {:parse, source.parse(response.body), payload} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      rows =
        for code <- tracked(), %Decimal{} = rate <- [rates[code]] do
          %{
            currency: code,
            date: date,
            source: source.code(),
            rate: rate,
            raw_payload_id: payload.id,
            inserted_at: now
          }
        end

      Repo.insert_all(Rate, rows,
        on_conflict: {:replace, [:rate, :raw_payload_id, :inserted_at]},
        conflict_target: [:currency, :date, :source]
      )

      Ingestion.mark_parsed!(payload, source.parser_version())
      {:ok, date, length(rows)}
    else
      {:parse, {:error, reason}, payload} ->
        Ingestion.mark_parsed!(payload, source.parser_version(), inspect(reason))
        {:error, {:parse, reason}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "The days of the last `days` without a rate from the primary source, oldest first."
  def missing_days(days, today \\ Date.utc_today()) do
    first = Enum.max([Date.add(today, -days), ExchangeApi.first_day()], Date)

    have =
      Repo.all(
        from r in Rate,
          where: r.source == ^ExchangeApi.code() and r.date >= ^first,
          distinct: true,
          select: r.date
      )
      |> MapSet.new()

    Date.range(first, Date.add(today, -1))
    |> Enum.reject(&MapSet.member?(have, &1))
  end

  # Reading the table ----------------------------------------------------

  @doc "The first day with rates from a source, or nil."
  def first_stored_day(source \\ ExchangeApi) do
    Repo.one(from r in Rate, where: r.source == ^source.code(), select: min(r.date))
  end

  @doc "The latest day with rates from a source, or nil."
  def latest_day(source \\ ExchangeApi) do
    Repo.one(from r in Rate, where: r.source == ^source.code(), select: max(r.date))
  end

  @doc "The latest day on or before `day` with rates from a source, or nil."
  def day_on_or_before(day, source \\ ExchangeApi) do
    Repo.one(
      from r in Rate,
        where: r.source == ^source.code() and r.date <= ^day,
        select: max(r.date)
    )
  end

  @doc "Rates of a source on a day, `%{code => Decimal}`, as stored."
  def stored(day, source \\ ExchangeApi) do
    Repo.all(
      from r in Rate,
        where: r.source == ^source.code() and r.date == ^day,
        select: {r.currency, r.rate}
    )
    |> Map.new()
  end

  @doc """
  The published rates of a day: the primary source's, with every fixed peg
  computed from its anchor and the official parity. `%{code => Decimal}`.
  """
  def published(day) when is_nil(day), do: %{}

  def published(day) do
    day |> stored(ExchangeApi) |> apply_pegs()
  end

  @doc "Replaces the rate of every pegged currency by its anchor's rate times the parity."
  def apply_pegs(rates) do
    anchors = Map.put(rates, "USD", Decimal.new(1))

    Enum.reduce(Currencies.pegs(), rates, fn {code, {anchor, parity}}, acc ->
      case anchors[anchor] do
        %Decimal{} = a -> Map.put(acc, code, Decimal.mult(a, to_decimal(parity)))
        nil -> acc
      end
    end)
  end

  defp to_decimal(f) when is_float(f), do: Decimal.from_float(f)
  defp to_decimal(n) when is_integer(n), do: Decimal.new(n)

  # Publication ----------------------------------------------------------

  @doc """
  Builds the document of the pages from the latest primary day: rates,
  those of about a year earlier, and per-currency checks:

    * `"gap"`: the check source differs by more than 2% (floating currencies);
    * `"jump"`: more than 10% against the dollar since the previous day;
    * `"year_move"`: more than 10% against the dollar over the year, to be
      read with care (a real devaluation or a source error).

  Returns the document, or nil when nothing is stored yet.
  """
  def publish! do
    case latest_day(ExchangeApi) do
      nil ->
        nil

      day ->
        doc = build(day)
        Snapshots.store!(@snapshot, doc)
        SyliAtlas.Market.refresh_data_version()
        doc
    end
  end

  @doc false
  def build(day) do
    now = published(day)
    # The previous rate only counts if it is recent (a weekend, a missed night).
    previous_day =
      case day_on_or_before(Date.add(day, -1)) do
        %Date{} = d -> if Date.diff(day, d) <= 4, do: d
        nil -> nil
      end

    previous = published(previous_day)

    year_day =
      case day_on_or_before(Date.add(day, -365)) do
        %Date{} = d -> if Date.diff(day, d) <= 372, do: d
        nil -> nil
      end

    year = published(year_day)
    shadow_day = latest_day(ErApi)

    shadow =
      if shadow_day && abs(Date.diff(day, shadow_day)) <= 2,
        do: stored(shadow_day, ErApi),
        else: %{}

    flags =
      for code <- tracked(), rate <- [now[code]], rate != nil, into: %{} do
        list =
          [
            (Currencies.peg(code) == nil and gap?(rate, shadow[code], 0.02)) && "gap",
            gap?(rate, previous[code], 0.10) && "jump",
            gap?(rate, year[code], 0.10) && "year_move"
          ]
          |> Enum.filter(& &1)

        {code, list}
      end
      |> Enum.reject(fn {_code, list} -> list == [] end)
      |> Map.new()

    %{
      "format" => @format,
      "as_of" => Date.to_iso8601(day),
      "year_ago" => year_day && Date.to_iso8601(year_day),
      "source" => %{
        "code" => ExchangeApi.code(),
        "name" => ExchangeApi.name(),
        "url" => ExchangeApi.url()
      },
      "check" => %{"code" => ErApi.code(), "day" => shadow_day && Date.to_iso8601(shadow_day)},
      "rates" => encode(now),
      "year_ago_rates" => encode(year),
      "flags" => flags,
      "pegs" =>
        for {code, {anchor, parity}} <- Currencies.pegs(), into: %{} do
          {code, %{"anchor" => anchor, "rate" => parity}}
        end
    }
  end

  defp encode(rates) do
    for {code, rate} <- rates,
        code in tracked(),
        into: %{},
        do: {code, Decimal.to_string(rate, :normal)}
  end

  defp gap?(_a, nil, _limit), do: false

  defp gap?(%Decimal{} = a, %Decimal{} = b, limit) do
    ratio = Decimal.div(a, b) |> Decimal.to_float()
    abs(ratio - 1) > limit
  end

  # Reading the document -------------------------------------------------

  @doc "The document of the pages, or nil before the first import."
  def latest, do: Snapshots.read(@snapshot)

  @doc "Units of `code` that one unit of `base` buys, in a document (float), or nil."
  def per(doc, code, base \\ "USD", key \\ "rates")
  def per(nil, _code, _base, _key), do: nil

  def per(doc, code, base, key) do
    with %{} = rates <- doc[key],
         c when not is_nil(c) <- rate(rates, code),
         b when not is_nil(b) <- rate(rates, base) do
      c / b
    else
      _ -> nil
    end
  end

  defp rate(_rates, "USD"), do: 1.0

  defp rate(rates, code) do
    case rates[code] do
      nil -> nil
      text -> text |> Decimal.new() |> Decimal.to_float()
    end
  end

  @doc """
  How much a currency gained (+) or lost (−) against `base` over the year,
  in percent, or nil without a rate a year earlier.
  """
  def change(doc, code, base \\ "USD") do
    with now when is_number(now) <- per(doc, code, base),
         ago when is_number(ago) <- per(doc, code, base, "year_ago_rates") do
      (ago / now - 1) * 100
    else
      _ -> nil
    end
  end

  @doc "Converts an amount between two tracked currencies (or USD) at the document's rates."
  def convert(doc, amount, from, to) when is_number(amount) do
    case per(doc, to, from) do
      nil -> nil
      r -> amount * r
    end
  end

  @doc "The checks raised for a currency in a document (`[\"gap\", \"jump\", \"year_move\"]`)."
  def flags(nil, _code), do: []
  def flags(doc, code), do: Map.get(doc["flags"] || %{}, code, [])
end
