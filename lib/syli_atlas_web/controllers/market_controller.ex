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

    paths = %{"fr" => Paths.markets("fr"), "en" => Paths.markets("en")}
    kept = %{"q" => q, "region" => region, "sort" => sort, "dir" => dir}
    filtered? = q != "" or region != nil or params["sort"] != nil

    render(conn, :index,
      page_title: gettext("African stock exchanges"),
      seo:
        Seo.page(
          locale,
          paths,
          gettext(
            "Every African stock exchange followed by Syli Atlas: main index, daily change, number of listed securities, with the source and date of each figure."
          ),
          %{noindex: filtered?}
        ),
      alternates: Seo.alternates_for_header(paths),
      overview: overview,
      exchanges: all,
      imported: overview["as_of"] != nil,
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
    paths = %{"fr" => Paths.exchange("fr", code), "en" => Paths.exchange("en", code)}
    page = Pagination.paginate(doc["securities"], params["page"], 20)

    render(conn, :exchange,
      page_title: e["short_name"] <> " · " <> gettext("stock exchange"),
      seo:
        Seo.page(locale, paths, answer(doc, locale), %{
          json_ld: [
            Seo.breadcrumbs([
              {"Syli Atlas", Paths.home(locale)},
              {gettext("Stock exchanges"), Paths.markets(locale)},
              {e["short_name"], paths[locale]}
            ])
          ],
          noindex: params["page"] not in [nil, "1"]
        }),
      alternates: Seo.alternates_for_header(paths),
      doc: doc,
      e: e,
      fx: Market.fx(),
      answer: answer(doc, locale),
      page: page,
      page_href: &Pagination.href(paths[locale], %{}, "page", &1, "securities")
    )
  end

  def security(conn, %{"exchange" => code, "ticker" => ticker}) do
    locale = conn.assigns.locale
    {doc, row} = Market.security(code, String.downcase(ticker)) || raise NotFoundError
    e = doc["exchange"]

    paths = %{
      "fr" => Paths.security("fr", code, row["ticker"]),
      "en" => Paths.security("en", code, row["ticker"])
    }

    if conn.request_path != paths[locale] do
      redirect(conn, to: paths[locale])
    else
      history = Market.security_history(row["id"])
      fx = Market.fx()
      session_value = doc["session"]["value"]

      share =
        if row["current"] and is_number(row["value"]) and is_number(session_value) and
             session_value > 0,
           do: row["value"] / session_value * 100

      render(conn, :security,
        page_title: row["name"] <> " (" <> row["ticker"] <> ") · " <> e["short_name"],
        seo:
          Seo.page(locale, paths, security_answer(row, e, locale), %{
            json_ld: [
              Seo.breadcrumbs([
                {"Syli Atlas", Paths.home(locale)},
                {gettext("Stock exchanges"), Paths.markets(locale)},
                {e["short_name"], Paths.exchange(locale, code)},
                {row["name"], paths[locale]}
              ])
            ]
          }),
        alternates: Seo.alternates_for_header(paths),
        doc: doc,
        e: e,
        row: row,
        history: history,
        fx: fx,
        share: share,
        country: Enum.find(e["country_names"], &(&1["code"] == row["country"])),
        answer: security_answer(row, e, locale)
      )
    end
  end

  def etfs(conn, _params) do
    locale = conn.assigns.locale
    doc = Market.etfs() || %{"etfs" => [], "sources" => [], "date" => nil, "value" => nil}
    paths = %{"fr" => Paths.etfs("fr"), "en" => Paths.etfs("en")}

    render(conn, :etfs,
      page_title: gettext("Funds exposed to Africa (ETF)"),
      seo:
        Seo.page(
          locale,
          paths,
          gettext(
            "Exchange-traded funds listed in Africa: price, daily change, volume and issuer."
          )
        ),
      alternates: Seo.alternates_for_header(paths),
      doc: doc,
      fx: Market.fx()
    )
  end

  # ---------------------------------------------------------------------------

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

  defp security_answer(row, e, locale) do
    alias SyliAtlasWeb.MarketComponents, as: M

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
  end
end
