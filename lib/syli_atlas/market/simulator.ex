defmodule SyliAtlas.Market.Simulator do
  @moduledoc """
  « If I had put X in this exchange on that day, what would I have
  today? », from the published closes of an exchange's main index
  (`market_index_values`) and our exchange rates (`SyliAtlas.Fx`).

  The index is a price index: dividends are not in it, and neither are
  fees, taxes or the difficulty of trading thin shares; the page says so.
  The value of the placement follows the index from the first session on
  or after the chosen day to the last published one. Converting to another
  currency uses the rate of the start and of the end day (fixed parities
  exactly, from `SyliAtlas.Economy.Currencies`).
  """
  import Ecto.Query
  alias SyliAtlas.Repo
  alias SyliAtlas.Economy.Currencies
  alias SyliAtlas.Fx
  alias SyliAtlas.Market.{IndexValue, Reference}

  @min_years 3

  @doc "Closes of an exchange's main index, oldest first: `[{Date, float}]`."
  def series(exchange_id) do
    Repo.all(
      from v in IndexValue,
        where: v.exchange_id == ^exchange_id,
        order_by: [asc: v.trade_date],
        select: {v.trade_date, v.value}
    )
    |> Enum.map(fn {d, v} -> {d, Decimal.to_float(v)} end)
  end

  @doc """
  The exchanges that can be simulated (at least #{@min_years} years of
  closes), with their first and last day: `[%{exchange, first, last}]`.
  """
  def available do
    spans =
      Repo.all(
        from v in IndexValue,
          group_by: v.exchange_id,
          select: {v.exchange_id, min(v.trade_date), max(v.trade_date), count()}
      )

    by_id = Map.new(Reference.list_exchanges(), &{&1.id, &1})

    for {id, first, last, n} <- spans,
        e = by_id[id],
        e != nil,
        first = to_date(first),
        last = to_date(last),
        Date.diff(last, first) >= 365 * @min_years and n > 200 do
      %{exchange: e, first: first, last: last}
    end
    |> Enum.sort_by(& &1.exchange.position)
  end

  defp to_date(%Date{} = d), do: d
  defp to_date(text) when is_binary(text), do: Date.from_iso8601!(text)

  @doc """
  Runs a placement of `amount` (in `currency`) on `series` from `start`.
  `index_currency` is the currency of the index. Returns nil when the
  series has nothing on or after `start`, or when a rate is missing.
  """
  def run(series, start, amount, currency, index_currency) do
    with [{d0, v0} | _] = from <-
           Enum.drop_while(series, fn {d, _} -> Date.compare(d, start) == :lt end),
         {d1, v1} = List.last(from),
         in_rate when is_number(in_rate) <- rate(currency, index_currency, d0),
         out_rate when is_number(out_rate) <- rate(index_currency, currency, d1) do
      # Units of the index currency put in, then each day's value in the
      # display currency at the end rate (the curve shows the index path).
      units = amount * in_rate
      value = fn v -> units * v / v0 * out_rate end
      final = value.(v1)
      days = Date.diff(d1, d0)
      years = days / 365.25

      %{
        start: d0,
        end: d1,
        amount: amount,
        currency: currency,
        index_currency: index_currency,
        final: final,
        gain_pct: (final / amount - 1) * 100,
        cagr: if(years >= 1, do: (:math.pow(final / amount, 1 / years) - 1) * 100),
        drawdown: drawdown(from),
        years: yearly(from, value),
        points: points(from, value),
        index_change: (v1 / v0 - 1) * 100,
        fx_effect: fx_effect(final, amount, v1 / v0)
      }
    else
      _ -> nil
    end
  end

  # The largest fall from a previous peak, in % (0 when none).
  defp drawdown(points) do
    {_peak, worst} =
      Enum.reduce(points, {nil, 0.0}, fn {_d, v}, {peak, worst} ->
        peak = if peak == nil or v > peak, do: v, else: peak
        {peak, min(worst, (v / peak - 1) * 100)}
      end)

    worst
  end

  # One row per calendar year: change of the index over the part of the
  # year held, and the value at the year's last session.
  defp yearly(points, value) do
    points
    |> Enum.chunk_by(fn {d, _} -> d.year end)
    |> Enum.reduce({[], nil}, fn chunk, {acc, prev_close} ->
      {first_d, first_v} = hd(chunk)
      {_last_d, last_v} = List.last(chunk)
      base = prev_close || first_v

      row = %{
        year: first_d.year,
        change: (last_v / base - 1) * 100,
        value: value.(last_v),
        partial: prev_close == nil and (first_d.month > 1 or first_d.day > 10)
      }

      {[row | acc], last_v}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  # At most one point a week for the curve, the first and last kept.
  defp points(points, value) do
    weekly =
      points
      |> Enum.chunk_by(fn {d, _} -> {d.year, div(Date.day_of_year(d) - 1, 7)} end)
      |> Enum.map(&hd/1)

    weekly =
      if List.last(weekly) == List.last(points), do: weekly, else: weekly ++ [List.last(points)]

    Enum.map(weekly, fn {d, v} -> {d, value.(v)} end)
  end

  # How much of the result comes from the exchange rate: the result minus
  # what the index alone gave, in points of %. Zero in the index currency.
  defp fx_effect(final, amount, index_ratio), do: (final / amount - index_ratio) * 100

  @doc """
  Units of `to` for one unit of `from` on `day` (or the closest day before,
  within a week): exact for fixed parities, else from our stored rates.
  """
  def rate(same, same, _day), do: 1.0

  def rate(from, to, day) do
    case {anchored(from), anchored(to)} do
      # Same anchor (e.g. EUR and XOF): the parities give the rate exactly.
      {{a, ka}, {a, kb}} ->
        kb / ka

      _ ->
        with {:ok, rates} <- rates_near(day),
             f when is_number(f) <- per_usd(rates, from),
             t when is_number(t) <- per_usd(rates, to) do
          t / f
        else
          _ -> nil
        end
    end
  end

  # A currency as {anchor, units per anchor unit}: itself at 1 when free.
  defp anchored(code) do
    case Currencies.peg(code) do
      %{anchor: anchor, rate: k} -> {anchor, k}
      nil -> {code, 1.0}
    end
  end

  defp rates_near(day) do
    case Fx.day_on_or_before(day) do
      %Date{} = d ->
        if Date.diff(day, d) <= 7, do: {:ok, Fx.published(d)}, else: :error

      nil ->
        :error
    end
  end

  defp per_usd(_rates, "USD"), do: 1.0

  defp per_usd(rates, code) do
    case rates[code] do
      %Decimal{} = r -> Decimal.to_float(r)
      _ -> nil
    end
  end

  @doc """
  The same placement started on 1 January of other years (and of the
  first year with data), for « when you start matters ».
  """
  def other_starts(series, amount, currency, index_currency, years) do
    for y <- years,
        r = run(series, Date.new!(y, 1, 1), amount, currency, index_currency),
        r != nil,
        r.start.year == y do
      %{year: y, final: r.final, cagr: r.cagr, drawdown: r.drawdown}
    end
  end
end
