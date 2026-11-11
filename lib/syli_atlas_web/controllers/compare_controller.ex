defmodule SyliAtlasWeb.CompareController do
  use SyliAtlasWeb, :controller

  alias SyliAtlas.Geo
  alias SyliAtlasWeb.{PageComponents, Paths, PublicData, Seo}

  plug :put_layout, false

  @max 6
  @colors ~w(--c1 --c2 --c3 --c4 --c5 --c6)

  def show(conn, params) do
    locale = conn.assigns.locale
    {from, to} = PageComponents.period(params)

    # ?add=slug appends an area (the picker works without JavaScript).
    slugs =
      (List.wrap(params["slugs"]) ++ List.wrap(params["add"]))
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    areas =
      slugs
      |> Enum.map(&Geo.get_area_by_slug(&1, locale))
      |> Enum.reject(&is_nil/1)
      |> Enum.take(@max)

    # A pair with a page of its own (SyliAtlasWeb.Topics): indexed in its
    # order; the other order keeps the reader's choice and names the first
    # as canonical.
    pair = length(areas) == 2 && SyliAtlasWeb.Topics.pair(Enum.map(areas, & &1.code))
    in_order? = pair && Enum.map(areas, & &1.code) == pair

    canonical_slugs = Enum.map(areas, &SyliAtlas.Geo.Area.slug(&1, locale))

    if params["add"] || canonical_slugs != List.wrap(params["slugs"]) do
      period = if params["from"] || params["to"], do: "?from=#{from}&to=#{to}", else: ""
      redirect(conn, to: Paths.compare(locale, canonical_slugs) <> period)
    else
      items = areas |> Enum.map(& &1.code) |> PublicData.compare(from, to)
      by_code = Map.new(items, &{&1["code"], &1})

      series =
        areas
        |> Enum.with_index()
        |> Enum.flat_map(fn {a, i} ->
          case by_code[a.code] do
            nil ->
              []

            item ->
              [
                %{
                  id: a.code,
                  name: item["name"][locale],
                  color: Enum.at(@colors, i),
                  item: item,
                  area: a
                }
              ]
          end
        end)

      names = Enum.map_join(series, ", ", & &1.name)

      paths = %{
        "fr" => Paths.compare("fr", Enum.map(areas, &SyliAtlas.Geo.Area.slug(&1, "fr"))),
        "en" => Paths.compare("en", Enum.map(areas, &SyliAtlas.Geo.Area.slug(&1, "en")))
      }

      # Only the pairs chosen in SyliAtlasWeb.Topics are indexed, over the
      # default period: free combinations would make thousands of near-copies.
      indexed? =
        in_order? == true and length(series) == 2 and is_nil(params["from"]) and
          is_nil(params["to"])

      reversed? = pair not in [nil, false] and in_order? == false and length(series) == 2

      title =
        cond do
          series == [] -> gettext("Compare")
          indexed? -> pair_title(series, to)
          true -> gettext("Compare %{names}", names: names)
        end

      description =
        if indexed?,
          do: pair_answer(series, from, to, locale),
          else:
            gettext("Growth, income, inflation and debt side by side: %{names}.", names: names)

      render(conn, :show,
        page_title: title,
        heading: if(indexed?, do: pair_heading(series), else: nil),
        answer: if(indexed?, do: description, else: nil),
        seo:
          Seo.page(locale, paths, description, %{
            noindex: not indexed? and not reversed?,
            json_ld:
              if(indexed?,
                do: [
                  Seo.breadcrumbs([
                    {"Syli Atlas", Paths.home(locale)},
                    {gettext("Compare"), Paths.compare(locale, [])},
                    {pair_heading(series), paths[locale]}
                  ])
                ],
                else: []
              )
          })
          |> then(fn seo ->
            if reversed?,
              do: Map.put(seo, :canonical, Seo.url(SyliAtlasWeb.Topics.pair_path(locale, pair))),
              else: seo
          end),
        alternates: Seo.alternates_for_header(paths),
        from: from,
        to: to,
        series: series,
        slugs: canonical_slugs,
        choices:
          Geo.list_areas() |> Enum.reject(&(&1.code in Enum.map(areas, fn a -> a.code end))),
        full?: length(areas) >= @max
      )
    end
  end

  defp pair_heading([a, b]), do: gettext("%{a} or %{b}?", a: a.name, b: b.name)

  defp pair_title([a, b], to),
    do:
      gettext("%{a} or %{b}: GDP, growth and debt compared (%{year})",
        a: a.name,
        b: b.name,
        year: to
      )

  # « Côte d'Ivoire : PIB réel +37,1 % depuis 2020 ; Sénégal : +31,1 % (FMI). »
  defp pair_answer(series, from, to, locale) do
    parts =
      for s <- series do
        item = s.item

        gettext("%{name}: real GDP %{change} since %{from}, GDP of %{gdp} in %{to}",
          name: s.name,
          change:
            SyliAtlasWeb.Format.change(item["real_gdp_change_pct"], "real_gdp_index", locale),
          from: from,
          gdp:
            SyliAtlasWeb.Format.value(
              SyliAtlasWeb.PublicData.at(item["series"]["gdp_usd_bn"], to),
              "gdp_usd_bn",
              locale
            ),
          to: to
        )
      end

    Enum.join(parts, if(locale == "fr", do: " ; ", else: "; ")) <> " " <> gettext("(IMF).")
  end
end
