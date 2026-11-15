defmodule SyliAtlasWeb.MarketController do
  @moduledoc """
  The stock exchange pages: every exchange, one exchange, one security, the
  funds. Each reads one precomputed document. Hidden (404) while no source
  licence allows public display, unless the market section is in preview.
  """
  use SyliAtlasWeb, :controller

  alias SyliAtlas.Geo.Area
  alias SyliAtlas.Market
  alias SyliAtlasWeb.{NotFoundError, Pagination, Paths, Seo}

  plug :put_layout, false
  plug :ensure_public

  @regions ~w(west_africa north_africa central_africa east_africa southern_africa)
  @sorts ~w(listed name change close date)

  def index(conn, params) do
    locale = conn.assigns.locale
    overview = Market.overview() || %{"exchanges" => [], "totals" => %{}, "sources" => []}
    all = overview["exchanges"]

    q = params |> Map.get("q", "") |> to_string() |> String.trim() |> String.slice(0, 60)
    region = if params["region"] in @regions, do: params["region"], else: nil
    sort = if params["sort"] in @sorts, do: params["sort"], else: "listed"
    dir = if params["dir"] in ~w(asc desc), do: params["dir"], else: default_dir(sort)

    rows =
      all
      |> Enum.filter(&(is_nil(region) or &1["exchange"]["region"] == region))
      |> Enum.filter(&matches?(&1, q))
      |> sort_rows(sort, dir, locale)

    counts =
      for r <- @regions,
          into: %{nil => length(all)},
          do: {r, Enum.count(all, &(&1["exchange"]["region"] == r))}

    paths = SyliAtlas.Locales.each(fn l -> Paths.markets(l) end)
    kept = %{"q" => q, "region" => region, "sort" => sort, "dir" => dir}
    filtered? = q != "" or region != nil or params["sort"] != nil

    render(conn, :index,
      page_title: gettext("African stock exchanges: indices, prices and latest session"),
      seo:
        Seo.page(
          locale,
          paths,
          gettext(
            "Every African stock exchange followed by Syli Atlas: main index, daily change, number of listed securities, with the source and date of each figure."
          ),
          %{
            noindex: filtered?,
            json_ld: [
              Seo.breadcrumbs([
                {"Syli Atlas", Paths.home(locale)},
                {gettext("Stock exchanges"), paths[locale]}
              ]),
              Seo.item_list(
                gettext("African stock exchanges"),
                for(
                  x <- all,
                  do: {x["exchange"]["name"], Paths.exchange(locale, x["exchange"]["code"])}
                )
              )
            ]
          }
        ),
      alternates: Seo.alternates_for_header(paths),
      overview: overview,
      exchanges: all,
      imported: overview["as_of"] != nil,
      breadth: breadth(all),
      rows: rows,
      q: q,
      region: region,
      regions: @regions,
      counts: counts,
      sort: sort,
      dir: dir,
      kept: kept
    )
  end

  def exchange(conn, %{"exchange" => code} = params) do
    locale = conn.assigns.locale
    doc = Market.exchange(code) || raise NotFoundError
    e = doc["exchange"]
    paths = SyliAtlas.Locales.each(fn l -> Paths.exchange(l, code) end)
    page = Pagination.paginate(doc["securities"], params["page"], 20)
    simulable = Enum.any?(SyliAtlas.Market.Simulator.available(), &(&1.exchange.code == code))

    render(conn, :exchange,
      page_title: exchange_title(e, doc),
      simulable: simulable,
      seo:
        Seo.page(locale, paths, answer(doc, locale), %{
          json_ld: [
            Seo.breadcrumbs([
              {"Syli Atlas", Paths.home(locale)},
              {gettext("Stock exchanges"), Paths.markets(locale)},
              {e["short_name"], paths[locale]}
            ]),
            # Prices are shown here under the source's licence, not handed out:
            # the dataset has no download.
            Seo.dataset(
              name: exchange_title(e, doc),
              description: answer(doc, locale),
              path: paths[locale],
              locale: locale,
              area: %{name: e["name"]},
              based_on: {SyliAtlas.Market.Catalog.name(doc["index"]["source"] || "mansa"), nil},
              modified: doc["index"]["date"] || doc["as_of"]
            )
          ],
          noindex: params["page"] not in [nil, "1"]
        }),
      alternates: Seo.alternates_for_header(paths),
      doc: doc,
      e: e,
      fx: Market.fx(),
      answer: answer(doc, locale),
      # The other exchanges of the region: the small ones are reached from
      # their neighbours, not only from the list.
      neighbours:
        for(
          x <- (Market.overview() || %{})["exchanges"] || [],
          x["exchange"]["code"] != code,
          x["exchange"]["region"] == e["region"],
          do: x
        ),
      page: page,
      page_href: &Pagination.href(paths[locale], %{}, "page", &1, "securities")
    )
  end

  def security(conn, %{"exchange" => code, "ticker" => ticker}) do
    locale = conn.assigns.locale
    {doc, row} = Market.security(code, String.downcase(ticker)) || raise NotFoundError
    e = doc["exchange"]

    paths = SyliAtlas.Locales.each(fn l -> Paths.security(l, code, row["ticker"]) end)

    if conn.request_path != paths[locale] do
      conn |> put_status(301) |> redirect(to: paths[locale])
    else
      render_security(conn, doc, row, e, paths)
    end
  end

  defp render_security(conn, doc, row, e, paths) do
    alias SyliAtlas.Market.{Profiles, SecurityStats}

    locale = conn.assigns.locale
    sessions = Market.security_sessions(row["id"])
    history = for s <- sessions, s["close"], do: [s["date"], s["close"]]
    fx = Market.fx()
    session_value = doc["session"]["value"]

    share =
      if row["current"] and is_number(row["value"]) and is_number(session_value) and
           session_value > 0,
         do: row["value"] / session_value * 100

    listings = Profiles.listings(e["code"], row["ticker"])
    stats = SecurityStats.compute(sessions, doc["history"], doc["securities"], row)
    country = Enum.find(e["country_names"], &(&1["code"] == row["country"]))
    context = SyliAtlasWeb.CountryContext.get(row["country"], locale)
    usd = Market.to_usd(SyliAtlasWeb.MarketComponents.to_f(row["close"]), row["currency"], fx)

    peer_tickers = Profiles.peers(e["code"], row["ticker"])

    peers =
      for r <- doc["securities"], r["ticker"] in peer_tickers, do: r

    answer = security_answer(row, e, listings, locale)
    faq = security_faq(row, e, listings, usd, Profiles.about(e["code"], row["ticker"], locale), locale)

    render(conn, :security,
      page_title: security_title(row, e, listings),
      seo:
        Seo.page(locale, paths, security_description(answer, share, e, context, locale), %{
          json_ld: [
            Seo.breadcrumbs([
              {"Syli Atlas", Paths.home(locale)},
              {gettext("Stock exchanges"), Paths.markets(locale)},
              {e["short_name"], Paths.exchange(locale, e["code"])},
              {row["name"], paths[locale]}
            ]),
            Seo.corporation(row["name"], row["ticker"], e["short_name"], paths[locale],
              listings: Enum.map(listings, &{&1["exchange"], &1["ticker"]}),
              isin: row["isin"] || Profiles.get(e["code"], row["ticker"])["isin"]
            ),
            Seo.faq(faq)
          ]
        }),
      alternates: Seo.alternates_for_header(paths),
      doc: doc,
      e: e,
      row: row,
      history: history,
      sessions: sessions,
      fx: fx,
      share: share,
      country: country,
      context: context,
      listings: listings,
      isin: row["isin"] || Profiles.get(e["code"], row["ticker"])["isin"],
      sector: Profiles.sector_name(e["code"], row["ticker"], locale),
      about: Profiles.about(e["code"], row["ticker"], locale),
      stats: stats,
      peers: peers,
      faq: faq,
      answer: answer
    )
  end

  # « Sibanye-Stillwater (SSW / SBSW): price on the JSE, volume and history »:
  # people search the code they know, often the one of another market.
  defp security_title(row, e, listings) do
    gettext("%{name} (%{codes}): price on the %{exchange}, volume and history",
      name: row["name"],
      codes: Enum.join([row["ticker"] | Enum.map(listings, & &1["ticker"])], " / "),
      exchange: e["short_name"]
    )
  end

  defp security_description(answer, share, e, context, locale) do
    extra =
      cond do
        is_number(share) and share >= 0.5 ->
          gettext("%{share} % of the trading of the %{exchange} that day.",
            share: SyliAtlasWeb.Format.number(share, 0, locale),
            exchange: e["short_name"]
          )

        context && context.name ->
          gettext("Country: %{name}.", name: context.name)

        true ->
          nil
      end

    Enum.join(Enum.reject([answer, extra], &is_nil/1), " ")
  end

  defp security_faq(row, e, listings, usd, about, locale) do
    alias SyliAtlasWeb.MarketComponents, as: M

    other =
      for l <- listings do
        {gettext("What is the code of %{name} on the %{exchange}?",
           name: row["name"],
           exchange: l["exchange"]
         ), listing_sentence(row, l)}
      end

    where =
      {gettext("Where is %{name} listed?", name: row["name"]),
       Enum.join(
         [
           gettext("On the %{exchange} under the code %{ticker}, in %{currency}.",
             exchange: e["short_name"],
             ticker: row["ticker"],
             currency: row["currency"]
           )
           | for(
               l <- listings,
               do: gettext("On the %{exchange} under the code %{ticker}.",
                 exchange: l["exchange"],
                 ticker: l["ticker"]
               )
             )
         ],
         " "
       )}

    dollars =
      if is_number(usd) and row["close"] do
        [
          {gettext("How much is a %{ticker} share in dollars?", ticker: row["ticker"]),
           gettext(
             "About %{usd} at the close of %{date} (%{price} %{currency}), at the day's exchange rate.",
             usd: SyliAtlasWeb.MarketComponents.usd(usd, locale),
             date: M.day(row["trade_date"], locale),
             price: M.price(row["close"], locale),
             currency: row["currency"]
           )}
        ]
      else
        []
      end

    business =
      if about,
        do: [{gettext("What does %{name} do?", name: row["name"]), about}],
        else: []

    other ++ [where] ++ dollars ++ business
  end

  defp listing_sentence(row, %{"shares_per_receipt" => n} = l) when is_integer(n) do
    gettext(
      "%{code} on the %{exchange}. One depositary receipt %{code} stands for %{n} shares %{ticker} listed on the home exchange.",
      code: l["ticker"],
      exchange: l["exchange"],
      n: n,
      ticker: row["ticker"]
    )
  end

  defp listing_sentence(_row, l),
    do: gettext("%{code} on the %{exchange}.", code: l["ticker"], exchange: l["exchange"])

  def etfs(conn, _params) do
    locale = conn.assigns.locale
    doc = Market.etfs() || %{"etfs" => [], "sources" => [], "date" => nil, "value" => nil}
    paths = SyliAtlas.Locales.each(fn l -> Paths.etfs(l) end)

    render(conn, :etfs,
      page_title: gettext("Funds exposed to Africa (ETF): prices and daily change"),
      seo:
        Seo.page(
          locale,
          paths,
          gettext(
            "Exchange-traded funds listed in Africa: price, daily change, volume and issuer."
          ),
          %{
            json_ld: [
              Seo.breadcrumbs([
                {"Syli Atlas", Paths.home(locale)},
                {gettext("Stock exchanges"), Paths.markets(locale)},
                {"ETF", paths[locale]}
              ])
            ]
          }
        ),
      alternates: Seo.alternates_for_header(paths),
      doc: doc,
      fx: Market.fx()
    )
  end

  # ---------------------------------------------------------------------------

  defp exchange_title(e, doc) do
    count = length(doc["securities"] || [])

    if e["index_name"],
      do:
        gettext("%{name}: %{index} index and prices of the %{count} listed securities",
          name: e["short_name"],
          index: e["index_name"],
          count: count
        ),
      else:
        gettext("%{name}: prices of the %{count} listed securities",
          name: e["short_name"],
          count: count
        )
  end

  defp ensure_public(conn, _opts) do
    if Market.public?(), do: conn, else: raise(NotFoundError)
  end

  defp matches?(_row, ""), do: true

  defp matches?(row, q) do
    needle = Area.normalize(q)
    String.contains?(row["exchange"]["search"] || "", needle)
  end

  defp default_dir(sort) when sort in ~w(listed change close date), do: "desc"
  defp default_dir(_), do: "asc"

  defp sort_rows(rows, sort, dir, _locale) do
    {with_value, without} = Enum.split_with(rows, &(sort_key(&1, sort) != nil))

    sorted =
      Enum.sort_by(with_value, &sort_key(&1, sort), if(dir == "asc", do: :asc, else: :desc))

    sorted ++ Enum.sort_by(without, & &1["exchange"]["position"])
  end

  defp sort_key(r, "listed"), do: r["exchange"]["listed"]
  defp sort_key(r, "name"), do: String.downcase(r["exchange"]["short_name"])
  defp sort_key(r, "change"), do: SyliAtlasWeb.MarketComponents.to_f(r["index"]["change_pct"])
  defp sort_key(r, "close"), do: SyliAtlasWeb.MarketComponents.to_f(r["index"]["value"])
  defp sort_key(r, "date"), do: r["index"]["date"]

  @doc false
  def answer(%{"exchange" => e, "index" => i}, locale) do
    alias SyliAtlasWeb.MarketComponents, as: M

    cond do
      i["value"] && i["ytd_pct"] ->
        gettext(
          "The %{index} closed at %{value} points on %{date} (%{change}). Since 1 January: %{ytd}, according to %{source}.",
          index: e["index_name"] || e["short_name"],
          value: M.price(i["value"], locale),
          date: M.day(i["date"], locale),
          change: M.pct(i["change_pct"], locale),
          ytd: M.ytd(i["ytd_pct"], locale),
          source: SyliAtlas.Market.Catalog.name(i["source"])
        )

      i["value"] ->
        gettext("The %{index} closed at %{value} points on %{date} (%{change}).",
          index: e["index_name"] || e["short_name"],
          value: M.price(i["value"], locale),
          date: M.day(i["date"], locale),
          change: M.pct(i["change_pct"], locale)
        )

      true ->
        gettext("%{name}: %{count} listed securities. Its index is not provided by our source.",
          name: e["name"],
          count: e["listed"]
        )
    end
  end

  defp security_answer(row, e, listings, locale) do
    alias SyliAtlasWeb.MarketComponents, as: M

    base =
      if row["close"] do
        gettext(
          "%{name} (%{ticker}) closed at %{price} %{currency} on %{date} on the %{exchange} (%{change}).",
          name: row["name"],
          ticker: row["ticker"],
          price: M.price(row["close"], locale),
          currency: row["currency"],
          date: M.day(row["trade_date"], locale),
          exchange: e["short_name"],
          change: M.pct(row["change_pct"], locale)
        )
      else
        gettext("%{name} (%{ticker}), listed on the %{exchange}.",
          name: row["name"],
          ticker: row["ticker"],
          exchange: e["short_name"]
        )
      end

    also =
      for l <- listings do
        if is_integer(l["shares_per_receipt"]) do
          gettext("Also listed on the %{exchange} (%{code}, 1 receipt = %{n} shares).",
            exchange: l["exchange"],
            code: l["ticker"],
            n: l["shares_per_receipt"]
          )
        else
          gettext("Also listed on the %{exchange} (%{code}).",
            exchange: l["exchange"],
            code: l["ticker"]
          )
        end
      end

    Enum.join([base | also], " ")
  end

  # Indices up and down at their last session, and exchanges whose index
  # the source does not give.
  defp breadth(exchanges) do
    changes =
      for x <- exchanges,
          x["index"]["value"] != nil,
          do: SyliAtlasWeb.MarketComponents.to_f(x["index"]["change_pct"])

    %{
      up: Enum.count(changes, &(&1 && &1 > 0)),
      down: Enum.count(changes, &(&1 && &1 < 0)),
      missing: Enum.count(exchanges, &(&1["index"]["value"] == nil))
    }
  end
end
