defmodule SyliAtlasWeb.AreaController do
  use SyliAtlasWeb, :controller

  alias SyliAtlas.Geo
  alias SyliAtlas.Geo.Area
  import SyliAtlasWeb.Format, only: [change: 3, value: 3]
  alias SyliAtlasWeb.{NotFoundError, PageComponents, Pagination, Paths, PublicData, Seo}
  alias SyliAtlas.Economy.{Convergence, Currencies}
  alias SyliAtlas.Sources.Indicators

  plug :put_layout, false

  @kpis ~w(gdp_usd_bn gdp_per_capita_usd inflation public_debt_pct_gdp)

  def show(conn, %{"slug" => slug} = params) do
    locale = conn.assigns.locale
    area = Geo.get_area_by_slug(slug, locale) || raise NotFoundError
    {from, to} = PageComponents.period(params)
    data = PublicData.area(area.code, from, to) || raise NotFoundError
    profile = data["profile"]
    paths = %{"fr" => Paths.area("fr", area), "en" => Paths.area("en", area)}

    # Old or foreign slug: send to the canonical URL.
    if conn.request_path != paths[locale] do
      redirect(conn, to: paths[locale] <> query(conn))
    else
      name = Area.name(area, locale)
      region = area.region_code && Geo.get_area_by_code(area.region_code)
      ranking_scope = if area.kind == "country", do: area.region_code, else: nil

      peers =
        if area.kind == "country" do
          PublicData.ranking("gdp_usd_bn", from, to, region: ranking_scope, locale: locale)
        else
          Geo.list_regions()
          |> Enum.map(&PublicData.area(&1.code, from, to))
          |> Enum.reject(&is_nil/1)
          |> Enum.map(fn r ->
            %{
              "code" => r["profile"]["code"],
              "name" => r["profile"]["name"][locale],
              "slug" => r["profile"]["slug"][locale],
              "kind" => r["profile"]["kind"],
              "value" => r["period"]["changes"]["gdp_usd_bn"]
            }
          end)
          |> Enum.sort_by(&(-(&1["value"] || -999)))
        end

      ratings = if area.kind == "country", do: SyliAtlas.Ratings.document()
      rating = SyliAtlas.Ratings.for_country(ratings, area.code)

      climate = area.kind == "country" && SyliAtlas.Climate.for_country(area.code)

      faq =
        faq(name, data, from, to, locale) ++
          SyliAtlasWeb.RatingComponents.faq_items(name, rating, ratings) ++
          SyliAtlasWeb.ClimateComponents.faq_items(name, climate)

      members = if(area.kind == "country", do: [], else: members(profile, from, to, locale))
      kept = Map.take(params, ~w(from to peers members))

      peers_page =
        Map.get(params, "peers") || Pagination.page_of(peers, &(&1["code"] == area.code))

      render(conn, :show,
        page_title: name <> " · " <> gettext("economy %{from}–%{to}", from: from, to: to),
        seo:
          Seo.page(locale, paths, answer(name, data, from, to, locale), %{
            json_ld: [
              Seo.breadcrumbs(breadcrumbs(area, region, locale)),
              Seo.dataset(
                gettext("Economy of %{name}, 2015–2030", name: name),
                name,
                "/api/v1/areas/#{area.code}",
                profile["edition"]
              ),
              Seo.faq(faq)
            ]
          }),
        alternates: Seo.alternates_for_header(paths),
        area: area,
        name: name,
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
        answer: answer(name, data, from, to, locale),
        members: Pagination.paginate(members, params["members"]),
        members_href: &Pagination.href(paths[locale], kept, "members", &1, "members"),
        members_max: bar_max(members),
        market: market(area),
        rating: rating,
        climate: climate,
        rated: (ratings && ratings["rated"]) || 0,
        comparison: comparison(area, region, from, to, locale),
        currency: currency(area, locale),
        fx: fx(area, locale),
        convergence:
          area.kind == "country" &&
            Convergence.check(area.code, profile["series"], to, Indicators.first_year()),
        world_bank: area.kind == "country" && SyliAtlas.WorldBank.for_country(area.code),
        world_bank_doc: SyliAtlas.WorldBank.document(),
        sections:
          sections(
            area,
            rating,
            climate,
            market(area),
            area.kind == "country" && SyliAtlas.WorldBank.for_country(area.code)
          )
      )
    end
  end

  # Anchors of the section menu, in page order.
  defp sections(area, rating, climate, market, wb) do
    latest = (wb && wb["latest"]) || %{}

    [{"economie", gettext("Economy")}, {"finances", gettext("Public finances")}] ++
      if(area.kind == "country", do: [{"monnaie", pgettext("section", "Currency")}], else: []) ++
      if(wb, do: [{"dette", gettext("Debt")}, {"flux", gettext("Financial inflows")}], else: []) ++
      if(wb, do: [{"emploi", gettext("Jobs")}], else: []) ++
      if(Enum.any?(~w(poverty gini electricity internet accounts), &latest[&1]),
        do: [{"conditions-de-vie", gettext("Living conditions")}],
        else: []
      ) ++
      if(rating, do: [{"notation", gettext("Rating")}], else: []) ++
      if(climate, do: [{"climat", gettext("Business climate")}], else: []) ++
      if(market != [], do: [{"market", gettext("Stock exchange")}], else: []) ++
      [{"questions", gettext("Questions")}]
  end

  # The line drawn next to a country (its region) or a region (Africa).
  defp comparison(area, region, from, to, locale) do
    other =
      cond do
        area.kind == "country" and region -> region
        area.kind == "region" -> Geo.get_area_by_code("africa")
        true -> nil
      end

    with %{} <- other, %{"profile" => p} <- PublicData.area(other.code, from, to) do
      %{name: p["name"][locale], series: p["series"]}
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
    codes
    |> PublicData.compare(from, to)
    |> Enum.map(
      &%{
        "code" => &1["code"],
        "name" => &1["name"][locale],
        "slug" => &1["slug"][locale],
        "kind" => &1["kind"],
        "value" => &1["gdp_change_pct"]
      }
    )
    |> Enum.sort_by(&(-(&1["value"] || -999)))
  end

  defp members(_, _, _, _), do: []

  @doc false
  def answer(name, data, from, to, locale) do
    s = data["profile"]["series"]
    ch = data["period"]["changes"]

    gettext(
      "%{name}: GDP of %{gdp} in %{to} (IMF), %{change} since %{from} in current dollars. Growth in %{to}: %{growth}.",
      name: name,
      gdp: value(PublicData.at(s["gdp_usd_bn"], to), "gdp_usd_bn", locale),
      to: to,
      from: from,
      change: change(ch["gdp_usd_bn"], "gdp_usd_bn", locale),
      growth: value(PublicData.at(s["real_gdp_growth"], to), "real_gdp_growth", locale)
    )
  end

  defp faq(name, data, from, to, locale) do
    s = data["profile"]["series"]

    [
      {gettext("How much has the economy of %{name} grown since %{from}?", name: name, from: from),
       answer(name, data, from, to, locale)},
      {gettext("What is the GDP per capita of %{name}?", name: name),
       gettext(
         "%{value} in %{year} at market exchange rates, %{ppp} in purchasing power parity (IMF).",
         value: value(PublicData.at(s["gdp_per_capita_usd"], to), "gdp_per_capita_usd", locale),
         ppp: value(PublicData.at(s["gdp_per_capita_ppp"], to), "gdp_per_capita_ppp", locale),
         year: to
       )},
      {gettext("What is the inflation rate in %{name}?", name: name),
       gettext("%{value} in %{year}, average annual change in consumer prices (IMF).",
         value: value(PublicData.at(s["inflation"], to), "inflation", locale),
         year: to
       )},
      {gettext("What is the public debt of %{name}?", name: name),
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
            {gettext("Where does %{name} rank in Africa?", name: name),
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
