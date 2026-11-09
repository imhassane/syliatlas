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

      render(conn, :show,
        page_title:
          if(series == [],
            do: gettext("Compare"),
            else: gettext("Compare %{names}", names: names)
          ),
        seo:
          Seo.page(
            locale,
            paths,
            gettext("Growth, income, inflation and debt side by side: %{names}.", names: names),
            %{
              noindex: length(series) < 2
            }
          ),
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
end
