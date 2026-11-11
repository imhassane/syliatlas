defmodule SyliAtlas.Recaps.Content do
  @moduledoc """
  What a country recap says, for a list of countries and a period. Plain
  data; `SyliAtlas.Recaps.Emails` writes it.

  For each country:

    * `ratings`: the decisions of the period (newest first) and the
      current rating of each agency;
    * `market`: the main index of the country's exchange, its change over
      the period (last close of the period against the last close before
      it), only when the market figures may be shown and the quality checks
      did not flag the index;
    * `currency`: the fixed peg (CFA francs…) or the latest dollar rate;
    * `imf`: growth, inflation and public debt of the current year, in the
      published IMF edition.

  Countries with a rating decision in the period come first, then the
  order of the subscription.
  """
  import Ecto.Query

  alias SyliAtlas.{Geo, Market, Ratings, Repo, Sources}
  alias SyliAtlas.Accounts.AlertRules
  alias SyliAtlas.Economy.Currencies
  alias SyliAtlas.Ratings.Rating
  alias SyliAtlas.Sources.Observation

  @source "imf_weo"
  @indicators ~w(real_gdp_growth inflation public_debt_pct_gdp)

  @doc "The recap of `codes` for the period `from`..`to` (dates, inclusive)."
  def build(codes, from, to, locale) do
    areas = codes |> Enum.map(&Geo.get_area_by_code/1) |> Enum.reject(&is_nil/1)
    year = AlertRules.watched_year(to)
    edition = Sources.published_edition(@source)
    figures = imf_figures(edition, Enum.map(areas, & &1.code), year)
    decisions = decisions(Enum.map(areas, & &1.code), from, to)
    ratings_doc = Ratings.document()
    market? = Market.public?()
    overview = if market?, do: Market.overview()
    fx = if market?, do: Market.fx()

    {countries, _docs} =
      Enum.map_reduce(areas, %{}, fn area, docs ->
        {market, docs} = market(area.code, overview, docs, from, to)

        country = %{
          code: area.code,
          name: Geo.Area.name(area, locale),
          area: area,
          ratings: %{
            decisions: Map.get(decisions, area.code, []),
            current: current_ratings(ratings_doc, area.code)
          },
          market: market,
          currency: currency(area.code, locale, fx),
          imf: Map.get(figures, area.code, %{})
        }

        {country, docs}
      end)

    countries =
      countries
      |> Enum.with_index()
      |> Enum.sort_by(fn {c, i} -> {if(c.ratings.decisions == [], do: 1, else: 0), i} end)
      |> Enum.map(&elem(&1, 0))

    %{
      from: from,
      to: to,
      year: year,
      countries: countries,
      edition: edition && %{code: edition.code, label: edition.label},
      status: edition && AlertRules.status(year, edition.code),
      new_edition?: new_edition?(edition, from, to),
      summary: summary(countries),
      market_sources: market_sources(countries)
    }
  end

  # IMF ---------------------------------------------------------------------

  defp imf_figures(nil, _codes, _year), do: %{}
  defp imf_figures(_edition, [], _year), do: %{}

  defp imf_figures(edition, codes, year) do
    Repo.all(
      from o in Observation,
        where:
          o.edition_id == ^edition.id and o.year == ^year and o.area_code in ^codes and
            o.indicator in ^@indicators,
        select: {o.area_code, o.indicator, o.value}
    )
    |> Enum.reject(fn {_, _, v} -> is_nil(v) end)
    |> Enum.group_by(&elem(&1, 0), fn {_, indicator, v} -> {indicator, to_float(v)} end)
    |> Map.new(fn {code, pairs} -> {code, Map.new(pairs)} end)
  end

  defp new_edition?(nil, _from, _to), do: false
  defp new_edition?(%{published_at: nil}, _from, _to), do: false

  defp new_edition?(%{published_at: at}, from, to) do
    day = DateTime.to_date(at)
    Date.compare(day, from) != :lt and Date.compare(day, to) != :gt
  end

  # Ratings -----------------------------------------------------------------

  defp decisions([], _from, _to), do: %{}

  defp decisions(codes, from, to) do
    Repo.all(
      from r in Rating,
        where:
          r.country_code in ^codes and r.action_date >= ^Date.to_iso8601(from) and
            r.action_date <= ^Date.to_iso8601(to),
        order_by: [desc: r.action_date, asc: r.agency]
    )
    |> Enum.group_by(& &1.country_code)
  end

  defp current_ratings(doc, code) do
    case Ratings.for_country(doc, code) do
      %{"agencies" => agencies} ->
        Enum.map(agencies, &%{agency: &1["agency"], rating: &1["rating"], outlook: &1["outlook"]})

      _ ->
        []
    end
  end

  # Market ------------------------------------------------------------------

  defp market(_code, nil, docs, _from, _to), do: {nil, docs}

  defp market(code, overview, docs, from, to) do
    case Market.for_country(code, overview) do
      [%{"exchange" => %{"code" => xcode} = exchange} | _] ->
        docs = Map.put_new_lazy(docs, xcode, fn -> Market.exchange(xcode) end)
        {index_move(exchange, docs[xcode], from, to), docs}

      _ ->
        {nil, docs}
    end
  end

  @doc false
  # The index change over the period, or nil when it cannot be told safely.
  def index_move(exchange, doc, from, to) do
    flags = get_in(doc || %{}, ["index", "flags"]) || %{}
    history = (doc && doc["history"]) || []

    with false <- Enum.any?(~w(missing stale suspect), &(flags[&1] == true)),
         [end_date, end_value] <- last_on_or_before(history, to),
         true <- Date.compare(Date.from_iso8601!(end_date), from) != :lt,
         [_, start_value] <- last_on_or_before(history, Date.add(from, -1)),
         start when start > 0 <- to_float(start_value) do
      final = to_float(end_value)

      %{
        exchange: exchange["code"],
        exchange_name: exchange["short_name"],
        index_name: exchange["index_name"],
        value: final,
        change_pct: Float.round((final - start) / start * 100, 1),
        date: end_date,
        sources: (doc["sources"] || []) |> Enum.map(& &1["code"])
      }
    else
      _ -> nil
    end
  end

  defp last_on_or_before(history, date) do
    iso = Date.to_iso8601(date)

    history
    |> Enum.filter(fn [d, _v] -> d <= iso end)
    |> List.last()
  end

  defp market_sources(countries) do
    countries
    |> Enum.flat_map(fn c -> (c.market && c.market.sources) || [] end)
    |> Enum.uniq()
  end

  # Currency ----------------------------------------------------------------

  defp currency(code, locale, fx) do
    case Currencies.for_country(code, locale) do
      %{code: cur, name: name, peg: %{} = peg} ->
        %{code: cur, name: name, peg: peg, rate: nil, as_of: nil}

      %{code: cur, name: name} ->
        case fx && get_in(fx, ["rates", "USD/" <> cur]) do
          rate when is_number(rate) ->
            %{code: cur, name: name, peg: nil, rate: rate, as_of: fx["as_of"]}

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  # Summary -----------------------------------------------------------------

  defp summary(countries) do
    moves =
      countries
      |> Enum.map(& &1.market)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq_by(& &1.exchange)

    %{
      decisions: countries |> Enum.map(&length(&1.ratings.decisions)) |> Enum.sum(),
      decided: countries |> Enum.reject(&(&1.ratings.decisions == [])) |> Enum.map(& &1.name),
      up: Enum.count(moves, &(&1.change_pct > 0)),
      down: Enum.count(moves, &(&1.change_pct < 0)),
      exchanges: length(moves)
    }
  end

  defp to_float(nil), do: nil
  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(n) when is_number(n), do: n * 1.0

  defp to_float(s) when is_binary(s) do
    case Float.parse(s) do
      {f, _} -> f
      :error -> nil
    end
  end
end
