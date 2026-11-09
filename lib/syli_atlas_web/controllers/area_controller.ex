defmodule SyliAtlasWeb.AreaController do
  use SyliAtlasWeb, :controller

  alias SyliAtlas.Geo
  alias SyliAtlas.Geo.Area
  import SyliAtlasWeb.Format, only: [change: 3, value: 3]
  alias SyliAtlasWeb.{NotFoundError, PageComponents, Pagination, Paths, PublicData, Seo}

  plug :put_layout, false

  @kpis ~w(real_gdp_index gdp_per_capita_usd inflation public_debt_pct_gdp)

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
          PublicData.ranking("real_gdp_index", from, to, region: ranking_scope, locale: locale)
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
              "value" => r["period"]["changes"]["real_gdp_index"]
            }
          end)
          |> Enum.sort_by(&(-(&1["value"] || -999)))
        end

      faq = faq(name, data, from, to, locale)
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
        members_max: bar_max(members)
      )
    end
  end

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
        "value" => &1["real_gdp_change_pct"]
      }
    )
    |> Enum.sort_by(&(-(&1["value"] || -999)))
  end

  defp members(_, _, _, _), do: []

  @doc false
  def answer(name, data, from, to, locale) do
    c = data["period"]["changes"]["real_gdp_index"]
    growth = PublicData.at(data["profile"]["series"]["real_gdp_growth"], to)

    gettext(
      "Between %{from} and %{to}, the real GDP of %{name} changed by %{change} (IMF). Growth in %{to}: %{growth}.",
      from: from,
      to: to,
      name: name,
      change: change(c, "real_gdp_index", locale),
      growth: value(growth, "real_gdp_growth", locale)
    )
  end

  defp faq(name, data, from, to, locale) do
    s = data["profile"]["series"]
    rank = data["profile"]["default_period"]["rank"] || %{}

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
      if rank["africa"] do
        {f, t} = SyliAtlas.Profiles.Builder.default_period()

        [
          {gettext("Where does %{name} rank in Africa?", name: name),
           gettext(
             "%{rank} out of %{of} African countries for real GDP growth between %{from} and %{to}.",
             rank: rank["africa"],
             of: rank["of_africa"],
             from: f,
             to: t
           )}
        ]
      else
        []
      end
  end
end
