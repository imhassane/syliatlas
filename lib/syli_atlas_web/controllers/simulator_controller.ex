defmodule SyliAtlasWeb.SimulatorController do
  @moduledoc """
  The placement simulator (canvas « Simulateur », variant B): « if I had put
  this amount in this exchange's index on that day, what would I have
  today? ». One GET form, so every result has its own address to share;
  the computation is in `SyliAtlas.Market.Simulator`.

  Hidden like the exchange pages while no licence allows public display.
  The closes are shown under the source's licence and never handed out:
  no download, no API.
  """
  use SyliAtlasWeb, :controller

  alias SyliAtlas.Economy.Currencies
  alias SyliAtlas.Fx
  alias SyliAtlas.Market
  alias SyliAtlas.Market.Simulator
  alias SyliAtlasWeb.{NotFoundError, Paths, Seo}

  plug :put_layout, false
  plug :ensure_public

  @bases ~w(EUR USD CNY)
  @presets [1, 3, 5, 10]
  @max_amount 1.0e12

  def index(conn, params) do
    locale = conn.assigns.locale
    available = Simulator.available()
    paths = SyliAtlas.Locales.each(fn l -> Paths.simulator(l) end)
    asked? = Enum.any?(~w(indice depuis montant devise), &Map.has_key?(params, &1))

    choice =
      Enum.find(available, &(&1.exchange.code == params["indice"])) ||
        Enum.find(available, &(&1.exchange.code == "brvm")) ||
        List.first(available)

    sim = choice && simulate(choice, params)

    render(conn, :index,
      page_title: title(sim),
      seo:
        Seo.page(locale, paths, description(sim, locale), %{
          noindex: asked?,
          json_ld: [
            Seo.breadcrumbs([
              {"Syli Atlas", Paths.home(locale)},
              {gettext("Stock exchanges"), Paths.markets(locale)},
              {gettext("Placement simulator"), paths[locale]}
            ]),
            web_app(paths[locale], locale)
          ]
        }),
      alternates: Seo.alternates_for_header(paths),
      available: available,
      sim: sim,
      share_url: sim && Seo.url(Paths.simulator(locale) <> "?" <> URI.encode_query(sim.query))
    )
  end

  defp simulate(%{exchange: e, first: first, last: last}, params) do
    index_currency = e.currency
    currencies = Enum.uniq([index_currency | @bases])
    default_currency = default_currency(index_currency)
    fx_from = Fx.first_stored_day()

    latest_start = Date.add(last, -30)

    start =
      case parse_date(params["depuis"]) do
        %Date{} = d -> clamp(d, first, latest_start)
        nil -> clamp(Date.add(last, -round(5 * 365.25)), first, latest_start)
      end

    asked_currency =
      if params["devise"] in currencies, do: params["devise"], else: default_currency

    # A currency other than the index's needs the rate of the start day:
    # exact for fixed parities, else from our stored history.
    {currency, fx_missing} =
      if convertible?(asked_currency, index_currency, start, fx_from),
        do: {asked_currency, nil},
        else: {index_currency, asked_currency}

    asked_amount = parse_amount(params["montant"])

    amount =
      cond do
        asked_amount == nil -> default_amount(currency)
        fx_missing == nil -> asked_amount
        # Shown in the index's currency: the amount asked, at today's rate.
        true -> in_currency(asked_amount, fx_missing, currency)
      end

    series = Simulator.series(e.id)
    result = Simulator.run(series, start, amount, currency, index_currency)

    years = Enum.to_list(first.year..(last.year - 1)//1) |> Enum.take(-10)
    others = Simulator.other_starts(series, amount, currency, index_currency, years)

    %{
      exchange: e,
      first: first,
      last: last,
      start: start,
      latest_start: latest_start,
      amount: amount,
      currency: currency,
      currencies: currencies,
      fx_missing: fx_missing,
      fixed_parity: same_anchor?(currency, index_currency),
      fx_from: fx_from,
      result: result,
      others: others,
      presets: presets(first, last),
      query: %{
        "indice" => e.code,
        "depuis" => Date.to_iso8601(start),
        "montant" => amount_param(amount),
        "devise" => currency
      }
    }
  end

  defp convertible?(same, same, _start, _fx_from), do: true

  defp convertible?(currency, index_currency, start, fx_from) do
    same_anchor?(currency, index_currency) or
      (fx_from != nil and Date.compare(start, fx_from) != :lt)
  end

  defp same_anchor?(a, b), do: anchor(a) == anchor(b)

  defp anchor(code) do
    case Currencies.peg(code) do
      %{anchor: anchor} -> anchor
      nil -> code
    end
  end

  # CFA franc indices are read in euros by default (the parity is fixed),
  # the others in dollars.
  defp default_currency(index_currency) do
    if anchor(index_currency) == "EUR", do: "EUR", else: "USD"
  end

  defp default_amount(c) when c in @bases, do: 1000.0

  # 1 000 dollars' worth, rounded to a round figure.
  defp default_amount(currency) do
    case Simulator.rate("USD", currency, Date.utc_today()) do
      r when is_number(r) -> round_figure(1000 * r)
      nil -> 1000.0
    end
  end

  defp in_currency(amount, from, to) do
    case Simulator.rate(from, to, Date.utc_today()) do
      r when is_number(r) -> round_figure(amount * r)
      nil -> amount
    end
  end

  defp round_figure(x) do
    magnitude = :math.pow(10, Float.floor(:math.log10(x)))
    Float.round(x / magnitude) * magnitude
  end

  defp presets(first, last) do
    years =
      for n <- @presets,
          d = Date.add(last, -round(n * 365.25)),
          Date.compare(d, first) != :lt,
          do: {n, d}

    years ++ [{:first, first}]
  end

  defp clamp(d, min, max) do
    cond do
      Date.compare(d, min) == :lt -> min
      Date.compare(d, max) == :gt -> max
      true -> d
    end
  end

  @doc false
  def parse_date(nil), do: nil

  def parse_date(text) when is_binary(text) do
    text = String.trim(text)

    case Date.from_iso8601(text) do
      {:ok, d} ->
        d

      _ ->
        case Integer.parse(text) do
          {y, ""} when y in 1990..2100 -> Date.new!(y, 1, 1)
          _ -> nil
        end
    end
  end

  def parse_date(_), do: nil

  @doc false
  def parse_amount(nil), do: nil

  def parse_amount(text) when is_binary(text) do
    cleaned = text |> String.replace([" ", " ", " ", "_"], "") |> String.replace(",", ".")

    case Float.parse(cleaned) do
      {x, ""} when x > 0 and x <= @max_amount -> x
      _ -> nil
    end
  end

  def parse_amount(_), do: nil

  defp amount_param(x) when x == trunc(x), do: Integer.to_string(trunc(x))
  defp amount_param(x), do: :erlang.float_to_binary(x, decimals: 2)

  defp title(%{exchange: e, result: %{}}),
    do: gettext("Placement simulator: what %{index} would have given", index: index_name(e))

  defp title(_), do: gettext("Placement simulator for African stock exchanges")

  defp description(%{result: %{} = r, exchange: e}, locale) do
    gettext(
      "%{amount} placed in the %{index} on %{start} would be worth %{final} on %{end} (%{gain}), dividends not included. Choose the index, the day and the amount.",
      amount: money(r.amount, r.currency, locale),
      index: index_name(e),
      start: day(r.start, locale),
      final: money(r.final, r.currency, locale),
      end: day(r.end, locale),
      gain: SyliAtlasWeb.CurrencyController.signed(r.gain_pct, locale)
    )
  end

  defp description(_, _locale) do
    gettext(
      "What an amount placed in an African stock exchange index on the day of your choice would be worth today, in the currency of your choice."
    )
  end

  defp web_app(path, locale) do
    %{
      "@context" => "https://schema.org",
      "@type" => "WebApplication",
      "name" => gettext("Placement simulator"),
      "url" => Seo.url(path),
      "applicationCategory" => "FinanceApplication",
      "operatingSystem" => "All",
      "inLanguage" => SyliAtlas.Locales.tag(locale),
      "isAccessibleForFree" => true,
      "offers" => %{"@type" => "Offer", "price" => "0", "priceCurrency" => "USD"},
      "description" =>
        gettext(
          "What an amount placed in an African stock exchange index on the day of your choice would be worth today, in the currency of your choice."
        ),
      "publisher" => %{"@type" => "Organization", "name" => "Syli Atlas"}
    }
  end

  @doc "The index's name, or the exchange's when it has none."
  def index_name(e), do: e.index_name || e.short_name

  @doc "An amount with its currency, the precision its size needs."
  def money(nil, _currency, _locale), do: "—"

  def money(x, currency, locale) do
    decimals = if abs(x) >= 1000, do: 0, else: 2
    text = SyliAtlasWeb.Format.number(x, decimals, locale)

    case currency do
      "EUR" -> text <> " €"
      "USD" -> if locale_base(locale) == "fr", do: text <> " $", else: "$" <> text
      c -> text <> " " <> c
    end
  end

  defp locale_base(locale), do: SyliAtlas.Locales.base(locale)

  @doc "A day in words."
  def day(%Date{} = d, locale),
    do: SyliAtlasWeb.Dates.day_month_year(d.day, d.month, d.year, locale, :long)

  defp ensure_public(conn, _opts) do
    if Market.public?(), do: conn, else: raise(NotFoundError)
  end
end
