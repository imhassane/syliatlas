defmodule SyliAtlasWeb.CurrencyController do
  @moduledoc """
  The African currencies and their exchange rates (SyliAtlas.Fx): the 42
  currencies against the dollar, the euro or the yuan, their regime, their
  change over a year, and a converter. One precomputed document is read;
  every option is a plain link or a GET form (no script), out of the index.
  """
  use SyliAtlasWeb, :controller

  alias SyliAtlas.Economy.Currencies
  alias SyliAtlas.Fx
  alias SyliAtlas.Geo.Names
  alias SyliAtlasWeb.{Paths, Seo}

  plug :put_layout, false

  @bases ~w(USD EUR CNY)
  @regimes ~w(floating EUR ZAR USD)
  @sorts ~w(change name)

  def index(conn, params) do
    locale = conn.assigns.locale
    doc = Fx.latest()

    base = params |> Map.get("base", "") |> to_string() |> String.upcase()
    base = if base in @bases, do: base, else: "USD"
    regime = if params["regime"] in @regimes, do: params["regime"], else: nil
    sort = if params["sort"] in @sorts, do: params["sort"], else: "change"

    all = rows(doc, base, locale)

    shown =
      all
      |> Enum.filter(&(is_nil(regime) or &1.regime == regime))
      |> sort_rows(sort, locale)

    counts =
      for r <- @regimes, into: %{nil => length(all)}, do: {r, Enum.count(all, &(&1.regime == r))}

    summary = summary(all)
    converter = converter(doc, params)
    paths = SyliAtlas.Locales.each(&Paths.currencies/1)
    kept = %{"base" => base, "regime" => regime, "sort" => sort}
    options? = Enum.any?(~w(base regime sort amount from to), &Map.has_key?(params, &1))
    answer = answer(summary, base, doc, locale)

    render(conn, :index,
      page_title: gettext("African currencies: exchange rates of the day"),
      seo:
        Seo.page(locale, paths, answer, %{
          noindex: options?,
          json_ld: [
            Seo.breadcrumbs([
              {"Syli Atlas", Paths.home(locale)},
              {gettext("African currencies"), paths[locale]}
            ]),
            Seo.dataset(
              name: gettext("Exchange rates of the African currencies"),
              description: answer,
              path: paths[locale],
              locale: locale,
              keywords: ~w(forex FCFA naira rand shilling cedi),
              variables: [{gettext("Units of currency per US dollar"), "USD"}],
              based_on: doc && {doc["source"]["name"], doc["source"]["url"]},
              modified: doc && doc["as_of"]
            )
          ]
        }),
      alternates: Seo.alternates_for_header(paths),
      doc: doc,
      base: base,
      bases: @bases,
      regime: regime,
      regimes: @regimes,
      sort: sort,
      counts: counts,
      rows: shown,
      summary: summary,
      converter: converter,
      choices: ["USD", "EUR", "CNY" | Currencies.codes()],
      picker: SyliAtlasWeb.Money.options(locale),
      kept: kept,
      answer: answer
    )
  end

  # One row per currency: names, countries, regime and the figures against `base`.
  defp rows(nil, _base, _locale), do: []

  defp rows(doc, base, locale) do
    # Country names from the in-memory search index (no query).
    names =
      for %{type: :country} = e <- SyliAtlasWeb.Search.Index.get(),
          into: %{},
          do: {e.code, SyliAtlas.Locales.pick(e.names, locale)}

    for code <- Currencies.codes() do
      countries = Currencies.countries_using(code)
      rate = Fx.per(doc, code, base)

      %{
        code: code,
        name: Currencies.name_of(code, locale),
        countries: countries,
        country_names: Enum.map(countries, &(names[&1] || Names.name(&1, locale) || &1)),
        regime: regime(code),
        rate: rate,
        per_thousand: rate && 1000 / rate,
        change: Fx.change(doc, code, base),
        flags: Fx.flags(doc, code)
      }
    end
  end

  defp regime(code) do
    case Currencies.peg(code) do
      %{anchor: anchor} -> anchor
      nil -> "floating"
    end
  end

  defp sort_rows(rows, "name", locale),
    do: Enum.sort_by(rows, &String.normalize(&1.name, :nfd), &collate(&1, &2, locale))

  defp sort_rows(rows, _change, _locale),
    do: Enum.sort_by(rows, &(&1.change || -1.0e9), :desc)

  defp collate(a, b, _locale), do: a <= b

  defp summary(rows) do
    known = Enum.filter(rows, &is_number(&1.change))
    sorted = Enum.sort_by(known, & &1.change, :desc)

    %{
      known: length(known),
      up: Enum.count(known, &(&1.change > 0.05)),
      down: Enum.count(known, &(&1.change < -0.05)),
      best: List.first(sorted),
      worst: List.last(sorted)
    }
  end

  # The converter's form: amount, from, to (defaults: 100 euros in CFA francs).
  defp converter(doc, params) do
    codes = ["USD", "EUR", "CNY" | Currencies.codes()]
    from = params |> Map.get("from", "EUR") |> to_string() |> String.upcase()
    from = if from in codes, do: from, else: "EUR"
    to = params |> Map.get("to", "XOF") |> to_string() |> String.upcase()
    to = if to in codes, do: to, else: "XOF"
    raw = params |> Map.get("amount", "100") |> to_string() |> String.slice(0, 20)

    amount =
      case raw
           |> String.replace(~r/[\s\x{00A0}\x{202F}]/u, "")
           |> String.replace(",", ".")
           |> Float.parse() do
        {n, ""} when n >= 0 and n < 1.0e15 -> n
        _ -> nil
      end

    %{
      raw: raw,
      amount: amount,
      from: from,
      to: to,
      result: amount && doc && Fx.convert(doc, amount, from, to),
      unit: doc && Fx.per(doc, to, from)
    }
  end

  defp answer(%{known: 0}, _base, _doc, _locale),
    do:
      gettext(
        "Exchange rates of the 42 African currencies against the dollar, the euro and the yuan, with their change over a year and a converter."
      )

  defp answer(s, base, doc, locale) do
    gettext(
      "On %{date}, %{down} of %{known} African currencies were worth less against the %{base} than a year earlier and %{up} were worth more. Largest rise: %{best} (%{best_change}); largest fall: %{worst} (%{worst_change}).",
      date: date_text(doc["as_of"], locale),
      down: s.down,
      known: s.known,
      up: s.up,
      base: base_name(base),
      best: s.best.name,
      best_change: signed(s.best.change, locale),
      worst: s.worst.name,
      worst_change: signed(s.worst.change, locale)
    )
  end

  @doc "A day in words from its ISO form."
  def date_text(nil, _locale), do: "—"

  def date_text(iso, locale) do
    d = Date.from_iso8601!(iso)
    SyliAtlasWeb.Dates.day_month_year(d.day, d.month, d.year, locale, :long)
  end

  @doc false
  def base_name("USD"), do: gettext("dollar")
  def base_name("EUR"), do: gettext("euro")
  def base_name("CNY"), do: gettext("yuan")

  @doc false
  def signed(nil, _locale), do: "—"

  def signed(c, locale) do
    sign =
      cond do
        c > 0.05 -> "+"
        c < -0.05 -> "−"
        true -> ""
      end

    sign <> SyliAtlasWeb.Format.number(abs(c), 1, locale) <> " %"
  end
end
