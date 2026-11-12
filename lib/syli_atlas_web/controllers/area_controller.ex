defmodule SyliAtlasWeb.AreaController do
  use SyliAtlasWeb, :controller

  alias SyliAtlas.Geo
  alias SyliAtlas.Geo.Area
  import SyliAtlasWeb.Format, only: [change: 3, value: 3, names: 1, names: 2]

  alias SyliAtlasWeb.{
    NotFoundError,
    PageComponents,
    Pagination,
    Paths,
    ProfileComponents,
    PublicData,
    Seo
  }

  alias SyliAtlas.Economy.{Convergence, Currencies}
  alias SyliAtlas.Sources.Indicators

  plug :put_layout, false

  @kpis ~w(gdp_usd_bn gdp_per_capita_usd inflation public_debt_pct_gdp)

  def show(conn, %{"slug" => slug} = params) do
    locale = conn.assigns.locale
    area = Geo.get_area_by_slug(slug, locale) || raise NotFoundError
    tab = tab(params["tab"])
    if area.kind != "country" and tab != :overview, do: raise(NotFoundError)

    {from, to} = PageComponents.period(params)
    data = PublicData.area(area.code, from, to) || raise NotFoundError

    paths = SyliAtlas.Locales.each(fn l -> Paths.area_tab(l, area, tab) end)

    # Old or foreign slug or tab name: send to the canonical URL.
    if conn.request_path != paths[locale] do
      # Permanent: the old address passes its links on to the canonical one.
      conn |> put_status(301) |> redirect(to: paths[locale] <> query(conn))
    else
      render_profile(conn, params, area, tab, data, from, to, paths)
    end
  end

  defp tab(nil), do: :overview
  defp tab(segment), do: Paths.tab_from_segment(segment) || raise(NotFoundError)

  defp render_profile(conn, params, area, tab, data, from, to, paths) do
    locale = conn.assigns.locale
    profile = data["profile"]
    country? = area.kind == "country"
    name = Area.name(area, locale)
    region = area.region_code && Geo.get_area_by_code(area.region_code)
    ranking_scope = if country?, do: area.region_code, else: nil

    peers =
      if country? do
        PublicData.ranking("gdp_usd_bn", from, to, region: ranking_scope, locale: locale)
      else
        Geo.list_regions()
        |> Enum.map(&PublicData.area(&1.code, from, to))
        |> Enum.reject(&is_nil/1)
        |> Enum.map(fn r ->
          %{
            "code" => r["profile"]["code"],
            "name" => SyliAtlas.Locales.pick(r["profile"]["name"], locale),
            "slug" => SyliAtlas.Locales.pick(r["profile"]["slug"], locale),
            "kind" => r["profile"]["kind"],
            "value" => r["period"]["changes"]["gdp_usd_bn"]
          }
        end)
        |> Enum.sort_by(&(-(&1["value"] || -999)))
      end

    ratings = if country?, do: SyliAtlas.Ratings.document()
    rating = SyliAtlas.Ratings.for_country(ratings, area.code)
    climate = country? && SyliAtlas.Climate.for_country(area.code)
    market = market(area)
    world_bank = country? && SyliAtlas.WorldBank.for_country(area.code)
    trade = country? && SyliAtlas.Trade.for_country(area.code)
    distress = country? && SyliAtlas.DebtDistress.for_country(area.code)
    tabs = tabs(area, rating, climate, market, world_bank, trade)
    if tab not in tabs, do: raise(NotFoundError)

    faq =
      faq(name, data, from, to, locale) ++
        SyliAtlasWeb.RatingComponents.faq_items(name, rating, ratings) ++
        SyliAtlasWeb.ClimateComponents.faq_items(name, climate)

    members = if(country?, do: [], else: members(profile, from, to, locale))
    kept = Map.take(params, ~w(from to peers members))

    peers_page =
      Map.get(params, "peers") || Pagination.page_of(peers, &(&1["code"] == area.code))

    currency = currency(area, locale)
    communities = if country?, do: SyliAtlas.Economy.Communities.for_country(area.code), else: []
    comparison = comparison(area, region, from, to, locale)
    tab_name = ProfileComponents.tab_label(tab)
    answer = tab_answer(tab, name, data, from, to, locale, world_bank, trade, rating, ratings)

    # A period chosen by the reader follows them from tab to tab (the default
    # one stays out of the address, which stays canonical).
    period_query = if params["from"] || params["to"], do: "?from=#{from}&to=#{to}", else: ""

    ctx = %{
      period_query: period_query,
      rated: (ratings && ratings["rated"]) || 0,
      locale: locale,
      area: area,
      name: name,
      tab: tab,
      tabs: tabs,
      profile: profile,
      data: data,
      from: from,
      to: to,
      world_bank: world_bank,
      trade: trade,
      trade_doc: SyliAtlas.Trade.document(),
      distress: distress,
      rating: rating,
      climate: climate,
      market: market,
      currency: currency,
      communities: communities,
      region_name: region && Area.name(region, locale),
      region_peers: if(country?, do: nearest(peers, area.code), else: []),
      slugs: country_slugs(locale)
    }

    title = title(tab, area, name, to, SyliAtlas.Trade.document())

    crumbs =
      breadcrumbs(area, region, locale) ++
        if(tab == :overview, do: [], else: [{tab_name, paths[locale]}])

    render(conn, :show,
      page_title: title,
      seo:
        Seo.page(locale, paths, answer, %{
          oembed:
            SyliAtlasWeb.Endpoint.url() <>
              "/oembed?url=" <> URI.encode_www_form(Seo.url(paths[locale])),
          json_ld:
            [Seo.breadcrumbs(crumbs)] ++
              datasets(tab, area, name, paths[locale], profile, trade, world_bank, locale) ++
              if(tab == :overview, do: [Seo.faq(faq)], else: [])
        }),
      alternates: Seo.alternates_for_header(paths),
      area: area,
      name: name,
      heading: if(tab == :overview, do: name, else: name <> " · " <> tab_name),
      tab: tab,
      tab_name: tab_name,
      tabs: tabs,
      path: paths[locale],
      ctx: ctx,
      region: region,
      data: data,
      profile: profile,
      from: from,
      to: to,
      kpis: @kpis,
      peers: Pagination.paginate(peers, peers_page),
      peers_href: &Pagination.href(paths[locale], kept, "peers", &1, "peers"),
      peers_max: bar_max(peers),
      faq: faq,
      answer: answer,
      members: Pagination.paginate(members, params["members"]),
      members_href: &Pagination.href(paths[locale], kept, "members", &1, "members"),
      members_max: bar_max(members),
      market: market,
      rating: rating,
      climate: climate,
      rated: (ratings && ratings["rated"]) || 0,
      comparison: comparison,
      currency: currency,
      fx: fx(area, locale),
      convergence:
        country? &&
          Convergence.check(area.code, profile["series"], to, Indicators.first_year()),
      world_bank: world_bank,
      world_bank_doc: SyliAtlas.WorldBank.document(),
      trade: trade,
      trade_doc: SyliAtlas.Trade.document()
    )
  end

  # One Dataset per source, on the page that shows it: the IMF series on the
  # overview, CEPII on Trade, the World Bank on Society. The other tabs show
  # the same IMF series again and carry none, so each dataset has one page.
  defp datasets(:overview, area, name, path, profile, _trade, _wb, locale) do
    edition = profile["edition"]
    to = edition_estimate_year(profile)

    [
      Seo.dataset(
        name: gettext("Economy of %{name}: GDP, growth, debt, inflation 2015–2030", names(name)),
        description:
          gettext(
            "Macroeconomic indicators of %{name} from 2015 to 2030: GDP in current dollars and in purchasing power parity, real growth, GDP per capita, inflation, public debt, fiscal balance, current account, population. Source: IMF, %{edition}. %{year} is an estimate, later years are projections.",
            names(name, edition: edition["label"], year: to)
          ),
        path: path,
        locale: locale,
        area: %{
          name: name,
          code: area.kind == "country" && area.code,
          alternate: SyliAtlas.Geo.French.usual_name(name)
        },
        keywords:
          for(
            k <- [gettext("GDP"), gettext("growth"), gettext("public debt"), gettext("inflation")],
            do: k <> " " <> name
          ),
        variables: [
          {gettext("GDP, current dollars"), gettext("billion USD")},
          {gettext("Real GDP growth"), "%"},
          {gettext("GDP per capita"), "USD"},
          {gettext("Inflation, annual average"), "%"},
          {gettext("Gross public debt"), gettext("% of GDP")},
          {gettext("Fiscal balance"), gettext("% of GDP")},
          {gettext("Current account balance"), gettext("% of GDP")}
        ],
        downloads: [
          {"text/csv", "/api/v1/areas/#{area.code}/csv"},
          {"application/json", "/api/v1/areas/#{area.code}"}
        ],
        based_on: {"IMF, " <> edition["label"], "https://www.imf.org/en/Publications/WEO"},
        modified: edition["fetched_at"],
        temporal: "2015/2030"
      )
    ]
  end

  defp datasets(:trade, area, name, path, _profile, trade, _wb, locale) when is_map(trade) do
    src = SyliAtlas.Trade.document()["source"]
    year = SyliAtlas.Trade.document()["year"]

    [
      Seo.dataset(
        name: gettext("Exports of %{name}: products and clients", names(name)),
        description:
          gettext(
            "Goods exported by %{name} in %{year}: share of each product chapter (HS) and of each client country. Source: %{source}, version %{version}.",
            names(name, year: year, source: src["name"], version: src["version"])
          ),
        path: path,
        locale: locale,
        area: %{name: name, code: area.code},
        based_on: {src["name"], src["url"]},
        modified: SyliAtlas.Trade.document()["as_of"],
        temporal: to_string(year)
      )
    ]
  end

  defp datasets(:society, area, name, path, _profile, _trade, wb, locale) when is_map(wb) do
    doc = SyliAtlas.WorldBank.document()
    src = doc["sources"]["wdi"]

    [
      Seo.dataset(
        name: gettext("Living conditions in %{name}: poverty, jobs, electricity", names(name)),
        description:
          gettext(
            "Social indicators of %{name}: poverty, unemployment, access to electricity and the internet, remittances, foreign investment, value added and jobs by sector. Source: %{source}.",
            names(name, source: src["name"])
          ),
        path: path,
        locale: locale,
        area: %{name: name, code: area.code},
        based_on: {src["name"], src["url"]},
        modified: doc["as_of"]
      )
    ]
  end

  defp datasets(_tab, _area, _name, _path, _profile, _trade, _wb, _locale), do: []

  # The last year the IMF gives as an estimate (the default arrival year).
  defp edition_estimate_year(_profile), do: elem(SyliAtlas.Profiles.Builder.default_period(), 1)

  # Titles name what people search: the subject, the measure, the year, the
  # source. A country also searched under another name has it in brackets
  # (Cabo Verde, Cap-Vert).
  defp title(:overview, area, name, to, _trade) do
    if area.kind == "country",
      do:
        gettext("%{name}: GDP, growth, debt and inflation %{year} (IMF)",
          name: usual(name),
          year: to
        ),
      else: gettext("%{name}: economy %{year}, GDP and growth (IMF)", name: name, year: to)
  end

  defp title(:economy, _area, name, _to, _trade),
    do: gettext("GDP of %{name} 2015–2030: growth and GDP per capita", title_names(name))

  defp title(:finances, _area, name, to, _trade),
    do:
      gettext(
        "Public debt of %{name}: level, creditors and risk (%{year})",
        title_names(name, year: to)
      )

  defp title(:trade, _area, name, _to, trade),
    do:
      gettext(
        "Exports of %{name}: products and main buyers (%{year})",
        title_names(name, year: (trade && trade["year"]) || "")
      )

  defp title(:society, _area, name, _to, _trade),
    do: gettext("%{name}: poverty, jobs and access to electricity", title_names(name))

  defp title(:markets, _area, name, _to, _trade),
    do: gettext("%{name}: credit rating, stock exchange and business climate", title_names(name))

  defp title_names(name, extra \\ []) do
    full = usual(name)

    for {k, v} <- names(name, extra) do
      if k in [:name, :of_name, :in_name, :the_name, :The_name],
        do: {k, String.replace(v, name, full)},
        else: {k, v}
    end
  end

  defp usual(name) do
    case Gettext.get_locale(SyliAtlasWeb.Gettext) == "fr" &&
           SyliAtlas.Geo.French.usual_name(name) do
      other when is_binary(other) -> "#{name} (#{other})"
      _ -> name
    end
  end

  # Tabs with something to show, in page order. A tab without data has no page.
  @doc "The tabs of a country profile that have data (sitemap, search)."
  def tabs_for(%{kind: "country"} = area) do
    tabs(
      area,
      SyliAtlas.Ratings.for_country(SyliAtlas.Ratings.document(), area.code),
      SyliAtlas.Climate.for_country(area.code),
      market(area),
      SyliAtlas.WorldBank.for_country(area.code),
      SyliAtlas.Trade.for_country(area.code)
    )
  end

  def tabs_for(_area), do: [:overview]

  defp tabs(%{kind: "country"}, rating, climate, market, world_bank, trade) do
    [:overview, :economy, :finances] ++
      if(trade, do: [:trade], else: []) ++
      if(world_bank, do: [:society], else: []) ++
      if(rating || climate || market != [], do: [:markets], else: [])
  end

  defp tabs(_area, _rating, _climate, _market, _wb, _trade), do: [:overview]

  # The five countries of the region closest in GDP, for the related links.
  defp nearest(peers, code) do
    case Enum.find_index(peers, &(&1["code"] == code)) do
      nil ->
        Enum.take(peers, 5)

      i ->
        peers
        |> Enum.with_index()
        |> Enum.reject(fn {_p, j} -> j == i end)
        |> Enum.sort_by(fn {_p, j} -> abs(j - i) end)
        |> Enum.take(5)
        |> Enum.map(&elem(&1, 0))
    end
  end

  defp country_slugs(locale) do
    for c <- Geo.list_countries(), into: %{} do
      {c.code, {Area.name(c, locale), Area.slug(c, locale)}}
    end
  end

  # The lead sentence of each tab: one figure, its year and its source.
  defp tab_answer(:finances, name, data, _from, to, locale, _wb, _trade, _r, _rs) do
    s = data["profile"]["series"]

    SyliAtlasWeb.EconomyComponents.finances_lead(
      name,
      PublicData.at(s["fiscal_balance_pct_gdp"], to),
      PublicData.at(s["public_debt_pct_gdp"], to),
      PublicData.at(s["current_account_pct_gdp"], to),
      to,
      locale
    )
  end

  defp tab_answer(:trade, name, _data, _from, _to, locale, _wb, trade, _r, _rs),
    do: SyliAtlasWeb.TradeComponents.lead(trade, SyliAtlas.Trade.document(), name, locale)

  defp tab_answer(:society, name, _data, _from, _to, locale, wb, _trade, _r, _rs) do
    l = wb["latest"]

    facts =
      [
        l["electricity"] &&
          gettext("%{v} of the population has electricity (%{year})",
            v: pct(l["electricity"]["value"], locale),
            year: l["electricity"]["year"]
          ),
        l["poverty"] &&
          gettext("%{v} live on less than $3.00 a day (%{year})",
            v: pct(l["poverty"]["value"], locale),
            year: l["poverty"]["year"]
          ),
        l["unemployment_ilo"] &&
          gettext("unemployment is %{v} (ILO, %{year})",
            v: pct(l["unemployment_ilo"]["value"], locale),
            year: l["unemployment_ilo"]["year"]
          )
      ]
      |> Enum.filter(& &1)

    case facts do
      [] ->
        gettext("%{name}: jobs, inflows and living conditions (World Bank).", name: name)

      _ ->
        gettext("%{name}: %{facts} (World Bank).", name: name, facts: Enum.join(facts, ", "))
    end
  end

  defp tab_answer(:markets, name, _data, _from, _to, _locale, _wb, _trade, rating, ratings) do
    case SyliAtlasWeb.RatingComponents.faq_items(name, rating, ratings) do
      [{_q, a} | _] -> a
      _ -> gettext("%{name}: stock exchange and business climate.", name: name)
    end
  end

  defp tab_answer(:economy, name, data, _from, to, locale, _wb, _trade, _r, _rs) do
    s = data["profile"]["series"]

    gettext(
      "GDP of %{name}: %{gdp} in %{to}, %{per_capita} per person (%{ppp} in purchasing power parity). Real growth of %{growth} in %{to} (IMF).",
      names(name,
        gdp: value(PublicData.at(s["gdp_usd_bn"], to), "gdp_usd_bn", locale),
        per_capita:
          value(PublicData.at(s["gdp_per_capita_usd"], to), "gdp_per_capita_usd", locale),
        ppp: value(PublicData.at(s["gdp_per_capita_ppp"], to), "gdp_per_capita_ppp", locale),
        growth: rate(PublicData.at(s["real_gdp_growth"], to), locale),
        to: to
      )
    )
  end

  defp tab_answer(_tab, name, data, from, to, locale, _wb, _trade, _r, _rs),
    do: answer(name, data, from, to, locale)

  defp pct(v, locale), do: SyliAtlasWeb.Format.number(v, 1, locale) <> " %"

  # A growth rate in a sentence: « 6,7 % », « −1,2 % », without the plus sign
  # of the tables.
  defp rate(nil, locale), do: SyliAtlasWeb.Format.number(nil, 1, locale)
  defp rate(v, locale), do: pct(v, locale)

  # The line drawn next to a country (its region) or a region (Africa).
  defp comparison(area, region, from, to, locale) do
    other =
      cond do
        area.kind == "country" and region -> region
        area.kind == "region" -> Geo.get_area_by_code("africa")
        true -> nil
      end

    with %{} <- other, %{"profile" => p} <- PublicData.area(other.code, from, to) do
      %{name: SyliAtlas.Locales.pick(p["name"], locale), series: p["series"]}
    else
      _ -> nil
    end
  end

  defp currency(%{kind: "country", code: code}, locale), do: Currencies.for_country(code, locale)
  defp currency(_area, _locale), do: nil

  # Dollar rate of the country's currency, when a market source allows showing it.
  defp fx(%{kind: "country", code: code}, locale) do
    with %{code: cur} <- Currencies.for_country(code, locale),
         true <- SyliAtlas.Market.public?(),
         %{"rates" => rates} = doc <- SyliAtlas.Market.fx(),
         rate when is_number(rate) <- rates["USD/" <> cur] do
      %{rate: rate, as_of: doc["as_of"]}
    else
      _ -> nil
    end
  end

  defp fx(_area, _locale), do: nil

  # The exchange(s) serving a country, when the market pages are public.
  defp market(%{kind: "country", code: code}) do
    if SyliAtlas.Market.public?(), do: SyliAtlas.Market.for_country(code), else: []
  end

  defp market(_area), do: []

  # Rank of a country among African economies by GDP in dollars in `to`.
  defp gdp_rank(%{"profile" => %{"kind" => "country", "code" => code}}, to) do
    rows =
      PublicData.ranking("gdp_usd_bn", to - 1, to, mode: "value")
      |> Enum.filter(&is_number(&1["value"]))

    case Enum.find_index(rows, &(&1["code"] == code)) do
      nil -> nil
      i -> {i + 1, length(rows)}
    end
  end

  defp gdp_rank(_data, _to), do: nil

  defp bar_max(rows), do: rows |> Enum.map(&abs(&1["value"] || 0)) |> Enum.max(fn -> 0 end)

  defp query(%{query_string: ""}), do: ""
  defp query(%{query_string: q}), do: "?" <> q

  defp breadcrumbs(area, region, locale) do
    [{"Syli Atlas", Paths.home(locale)}] ++
      if(region, do: [{Area.name(region, locale), Paths.area(locale, region)}], else: []) ++
      [{Area.name(area, locale), Paths.area(locale, area)}]
  end

  defp members(%{"members" => codes}, from, to, locale) when is_list(codes) and codes != [] do
    # The comparison query takes six areas at a time (the compare page's
    # limit): a region of fifteen countries is asked in three goes.
    codes
    |> Enum.chunk_every(6)
    |> Enum.flat_map(&PublicData.compare(&1, from, to))
    |> Enum.map(
      &%{
        "code" => &1["code"],
        "name" => SyliAtlas.Locales.pick(&1["name"], locale),
        "slug" => SyliAtlas.Locales.pick(&1["slug"], locale),
        "kind" => &1["kind"],
        "value" => &1["gdp_change_pct"]
      }
    )
    |> Enum.sort_by(&(-(&1["value"] || -999)))
  end

  defp members(_, _, _, _), do: []

  @doc """
  The lead sentence of a profile: real growth first (what the economy did),
  then the size and rank. GDP in current dollars comes last, and only when it
  tells another story than real growth (a currency that fell, as the naira
  since 2020): said alone, « −51.5 % » reads as a collapse.
  """
  def answer(name, data, from, to, locale) do
    s = data["profile"]["series"]
    ch = data["period"]["changes"]
    growth = rate(PublicData.at(s["real_gdp_growth"], to), locale)
    real = change(ch["real_gdp_index"], "real_gdp_index", locale)
    gdp = value(PublicData.at(s["gdp_usd_bn"], to), "gdp_usd_bn", locale)

    lead =
      case gdp_rank(data, to) do
        {rank, _of} ->
          gettext(
            "%{name}: growth of %{growth} in %{to}, real GDP %{real} since %{from} (IMF). GDP of %{gdp}, no. %{rank} in Africa.",
            name: name,
            growth: growth,
            to: to,
            real: real,
            from: from,
            gdp: gdp,
            rank: rank
          )

        nil ->
          gettext(
            "%{name}: growth of %{growth} in %{to}, real GDP %{real} since %{from} (IMF). GDP of %{gdp}.",
            name: name,
            growth: growth,
            to: to,
            real: real,
            from: from,
            gdp: gdp
          )
      end

    lead <> dollar_note(data, from, locale)
  end

  # GDP in current dollars, when it fell 20 points or more below real growth:
  # the gap is the exchange rate, said as such.
  defp dollar_note(data, from, locale) do
    ch = data["period"]["changes"]
    usd = ch["gdp_usd_bn"]
    real = ch["real_gdp_index"]

    with true <- is_number(usd) and is_number(real) and real - usd >= 20,
         %{name: currency} <- Currencies.for_country(data["profile"]["code"], locale) do
      " " <>
        gettext("In current dollars: %{change} since %{from}, as the %{currency} fell.",
          change: change(usd, "gdp_usd_bn", locale),
          from: from,
          currency: currency
        )
    else
      _ -> ""
    end
  end

  defp faq(name, data, from, to, locale) do
    s = data["profile"]["series"]

    [
      {gettext(
         "How much has the economy of %{name} grown since %{from}?",
         names(name, from: from)
       ), answer(name, data, from, to, locale)},
      {gettext("What is the GDP per capita of %{name}?", names(name)),
       gettext(
         "%{value} in %{year} at market exchange rates, %{ppp} in purchasing power parity (IMF).",
         value: value(PublicData.at(s["gdp_per_capita_usd"], to), "gdp_per_capita_usd", locale),
         ppp: value(PublicData.at(s["gdp_per_capita_ppp"], to), "gdp_per_capita_ppp", locale),
         year: to
       )},
      {gettext("What is the inflation rate in %{name}?", names(name)),
       gettext("%{value} in %{year}, average annual change in consumer prices (IMF).",
         value: value(PublicData.at(s["inflation"], to), "inflation", locale),
         year: to
       )},
      {gettext("What is the public debt of %{name}?", names(name)),
       gettext("%{value} of GDP in %{year}, gross debt of the general government (IMF).",
         value: value(PublicData.at(s["public_debt_pct_gdp"], to), "public_debt_pct_gdp", locale),
         year: to
       )}
    ] ++
      case gdp_rank(data, to) do
        nil ->
          []

        {rank, of} ->
          [
            {gettext("Where does %{name} rank in Africa?", names(name)),
             gettext(
               "Economy no. %{rank} of %{of} in Africa by GDP in current dollars in %{year} (IMF).",
               rank: rank,
               of: of,
               year: to
             )}
          ]
      end
  end
end
