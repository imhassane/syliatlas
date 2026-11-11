defmodule SyliAtlasWeb.RankingController do
  use SyliAtlasWeb, :controller

  alias SyliAtlas.Geo
  alias SyliAtlas.Sources.Indicators
  alias SyliAtlasWeb.{PageComponents, Pagination, Paths, PublicData, Seo, Topics}

  plug :put_layout, false

  @doc """
  The ranking chosen with the filters. Its default view (GDP, value in the
  arrival year) is indexed; an indicator with a page of its own sends there.
  """
  def index(conn, %{"indicator" => indicator} = params) when is_binary(indicator) do
    others = Map.drop(params, ["indicator"])

    if indicator in Topics.ranking_indicators() and others == %{} do
      conn
      |> put_status(301)
      |> redirect(to: Topics.ranking_path(conn.assigns.locale, indicator))
    else
      ranking(conn, params, nil)
    end
  end

  # The ranking's main address shows GDP: that page is /classement/pib.
  def index(conn, params) when map_size(params) == 0,
    do:
      conn
      |> put_status(301)
      |> redirect(to: Topics.ranking_path(conn.assigns.locale, "gdp_usd_bn"))

  def index(conn, params), do: ranking(conn, params, nil)

  @doc "A thematic ranking at its own address: /fr/classement/inflation."
  def topic(conn, %{"topic" => slug} = params) do
    locale = conn.assigns.locale
    indicator = Topics.ranking_indicator(slug) || raise SyliAtlasWeb.NotFoundError
    path = Topics.ranking_path(locale, indicator)

    if conn.request_path != path do
      conn |> put_status(301) |> redirect(to: path <> query(conn))
    else
      ranking(conn, Map.put(params, "indicator", indicator), indicator)
    end
  end

  defp query(%{query_string: ""}), do: ""
  defp query(%{query_string: q}), do: "?" <> q

  defp ranking(conn, params, topic) do
    locale = conn.assigns.locale
    {from, to} = PageComponents.period(params)

    indicator =
      if Indicators.valid?(params["indicator"]), do: params["indicator"], else: "gdp_usd_bn"

    # The value in the arrival year by default; the change over the period on
    # demand. Real GDP is an index (100 = the start year): only its change means
    # something.
    mode =
      if params["mode"] == "change" or indicator == "real_gdp_index", do: "change", else: "value"

    region = Enum.find(Geo.list_regions(), &(&1.code == params["region"]))

    rows =
      PublicData.ranking(indicator, from, to,
        mode: mode,
        region: region && region.code,
        locale: locale
      )

    {ranked, missing} = Enum.split_with(rows, &is_number(&1["value"]))
    ranked = if params["order"] == "asc", do: Enum.reverse(ranked), else: ranked
    page = Pagination.paginate(ranked, params["page"])

    kept =
      Map.take(params, ~w(mode region order from to) ++ if(topic, do: [], else: ["indicator"]))

    paths =
      if topic,
        do: SyliAtlas.Locales.each(fn l -> Topics.ranking_path(l, topic) end),
        else: SyliAtlas.Locales.each(fn l -> Paths.ranking(l) end)

    filtered? = map_size(kept) > 0 or page.page > 1
    title = Topics.ranking_title(indicator, to)

    render(conn, :index,
      page_title: title,
      heading: title,
      seo:
        Seo.page(
          locale,
          paths,
          ranking_answer(ranked, indicator, to, mode, locale),
          %{
            noindex: filtered?,
            json_ld: [
              Seo.breadcrumbs(
                [
                  {"Syli Atlas", Paths.home(locale)},
                  {gettext("Ranking"), Paths.ranking_main(locale)}
                ] ++
                  if(topic, do: [{title, paths[locale]}], else: [])
              ),
              Seo.item_list(
                title,
                for(
                  r <- Enum.take(ranked, 54),
                  do: {r["name"], Paths.area(locale, "country", r["slug"])}
                )
              )
            ]
          }
        ),
      alternates: Seo.alternates_for_header(paths),
      topic: topic,
      answer: ranking_answer(ranked, indicator, to, mode, locale),
      base_path: paths[locale],
      from: from,
      to: to,
      indicator: indicator,
      mode: mode,
      region: region,
      regions: Geo.list_regions(),
      order: params["order"] || "desc",
      page: page,
      page_href: &Pagination.href(paths[locale], kept, "page", &1, "ranking"),
      missing: missing,
      # Bars keep one scale across pages: the largest value of the ranking.
      bar_max: ranked |> Enum.map(&abs(&1["value"])) |> Enum.max(fn -> 0 end)
    )
  end

  # The first three, in a sentence a search engine or an assistant can quote.
  defp ranking_answer(ranked, indicator, to, mode, locale) do
    top =
      ranked
      |> Enum.take(3)
      |> Enum.map_join(", ", fn r ->
        "#{r["name"]} (#{format(r["value"], indicator, mode, locale)})"
      end)

    case top do
      "" ->
        gettext(
          "All African countries ranked by growth, income, inflation and debt, from IMF data."
        )

      _ ->
        gettext(
          "%{label}, %{year}: %{top}. The %{count} African countries ranked, from IMF data.",
          label: SyliAtlasWeb.PageComponents.indicator_label(indicator),
          year: to,
          top: top,
          count: length(ranked)
        )
    end
  end

  defp format(v, indicator, "change", locale),
    do: SyliAtlasWeb.Format.change(v, indicator, locale)

  defp format(v, indicator, _mode, locale), do: SyliAtlasWeb.Format.value(v, indicator, locale)
end
