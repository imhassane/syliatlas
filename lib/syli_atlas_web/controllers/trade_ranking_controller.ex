defmodule SyliAtlasWeb.TradeRankingController do
  @moduledoc """
  The three trade rankings of the 54 countries (SyliAtlas.TradeRankings):
  dependence on one product, raw materials, trade with the rest of Africa.
  One page each, at the ranking's address (`/fr/classement/matieres-premieres`),
  with a sentence that answers the question, the table of the 54 countries
  (region tabs, search, sort), the median, the questions of the page and
  the file of the table (`.csv`).

  Region, sort and search are plain links and a GET form: the filtered
  views are out of the index (`noindex`), the page itself is indexed.
  """
  use SyliAtlasWeb, :controller

  alias SyliAtlas.{Geo, Trade, TradeRankings}
  alias SyliAtlas.Geo.Area
  alias SyliAtlasWeb.{Export, Paths, Seo, TradeTopics}

  plug :put_layout, false

  @sorts ~w(value name)

  def show(conn, params) do
    locale = conn.assigns.locale
    id = conn.assigns.ranking
    doc = Trade.document()
    all = TradeRankings.rows(id, locale)
    regions = Geo.list_regions()
    region = Enum.find(regions, &(&1.code == params["region"]))
    sort = if params["sort"] in @sorts, do: params["sort"], else: "value"
    dir = if params["dir"] in ~w(asc desc), do: params["dir"], else: default_dir(sort)
    q = String.trim(params["q"] || "")

    shown =
      all
      |> Enum.filter(&(region == nil or &1.region == region.code))
      |> Enum.filter(&matches?(&1, q))
      |> sort_rows(sort, dir)

    median = TradeRankings.median(all)
    paths = SyliAtlas.Locales.each(&TradeTopics.ranking_path(&1, id))
    answer = answer(id, all, median, doc, locale)
    title = title(id, doc["year"])
    faq = faq(id, all, median, doc, locale)
    options? = Enum.any?(~w(region sort dir q), &Map.has_key?(params, &1))

    render(conn, :show,
      page_title: title,
      seo:
        Seo.page(locale, paths, answer, %{
          noindex: options?,
          json_ld: [
            Seo.breadcrumbs([
              {"Syli Atlas", Paths.home(locale)},
              {gettext("Ranking"), Paths.ranking_main(locale)},
              {TradeTopics.ranking_label(id), paths[locale]}
            ]),
            Seo.item_list(
              title,
              for(
                r <- all,
                is_number(r.value),
                do: {r.name, Paths.area(locale, "country", r.slug)}
              )
            ),
            Seo.dataset(
              name: title,
              description: answer,
              path: paths[locale],
              locale: locale,
              area: %{name: gettext("Africa")},
              temporal: to_string(doc["year"]),
              keywords: keywords(id),
              variables: [{value_label(id), "%"}, {gettext("Exports of goods"), "USD"}],
              based_on: {"CEPII, BACI", doc["source"]["url"]},
              downloads: [{"text/csv", TradeTopics.ranking_csv_path(locale, id)}]
            ),
            Seo.faq(faq)
          ]
        }),
      alternates: Seo.alternates_for_header(paths),
      id: id,
      title: title,
      answer: answer,
      doc: doc,
      all: all,
      rows: shown,
      ranks: TradeRankings.ranks(all),
      median: median,
      regions: regions,
      region: region,
      sort: sort,
      dir: dir,
      q: q,
      kept: %{"region" => region && region.code, "sort" => sort, "dir" => dir, "q" => q},
      counts:
        Map.new([nil | regions], fn
          nil -> {nil, length(all)}
          r -> {r.code, Enum.count(all, &(&1.region == r.code))}
        end),
      faq: faq,
      names: Map.new(all, &{&1.code, &1.name}),
      region_name: fn r -> Area.name(r, locale) end
    )
  end

  @doc "The table as a CSV file (`/fr/classement/matieres-premieres.csv`)."
  def csv(conn, params) do
    locale = conn.assigns.locale
    id = conn.assigns.ranking
    doc = Trade.document()
    rows = TradeRankings.rows(id, locale)
    ranks = TradeRankings.ranks(rows)
    sep = Export.separator(params["sep"], locale)

    header = [
      gettext("Rank"),
      gettext("Country"),
      gettext("ISO code"),
      value_label(id) <> " (%)",
      gettext("First product"),
      gettext("HS code"),
      gettext("Share of the first product (%)"),
      gettext("Exports of goods (US dollars)")
    ]

    body =
      Export.csv_document(
        about(doc, title(id, doc["year"]), TradeTopics.ranking_path(locale, id)),
        header,
        for r <- rows do
          [
            ranks[r.code],
            r.name,
            r.code,
            r.value,
            r.product && Trade.heading(doc, r.product, locale),
            r.product,
            r.product_share,
            r.exports
          ]
        end,
        sep
      )

    send_csv(
      conn,
      "syli-atlas_" <> TradeTopics.ranking_slug(id, locale) <> "_#{doc["year"]}.csv",
      body
    )
  end

  @doc false
  def about(doc, title, path) do
    [
      {gettext("Title"), title},
      {gettext("Source"),
       "CEPII, BACI (#{doc["source"]["version"]}), #{doc["source"]["license"]} · #{doc["source"]["url"]}"},
      {gettext("Calculation"), "Syli Atlas · " <> Seo.url(path)},
      {gettext("Year"), to_string(doc["year"])},
      {gettext("Downloaded on"), Date.to_iso8601(Date.utc_today())}
    ]
  end

  @doc false
  def send_csv(conn, filename, body) do
    conn
    |> put_resp_content_type("text/csv", "utf-8")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
    |> put_resp_header("x-robots-tag", "noindex")
    |> send_resp(200, body)
  end

  # Titles and sentences --------------------------------------------------------

  @doc false
  def title("dependence", year),
    do: gettext("African countries most dependent on one export product (%{year})", year: year)

  def title("raw", year),
    do: gettext("African countries that export the most raw materials (%{year})", year: year)

  def title("intra", year),
    do:
      gettext("African countries that sell the most to the rest of Africa (%{year})", year: year)

  @doc false
  def question("dependence"), do: gettext("Which African countries depend most on one product?")
  def question("raw"), do: gettext("Which African countries export the most raw materials?")

  def question("intra"),
    do: gettext("Which African countries sell the most to the rest of Africa?")

  @doc false
  def value_label("dependence"), do: gettext("Share of the first product")
  def value_label("raw"), do: gettext("Share of raw materials")
  def value_label("intra"), do: gettext("Share sold to Africa")

  defp keywords("dependence"),
    do: gettext("export dependence, export concentration, Africa, commodities, BACI")

  defp keywords("raw"),
    do: gettext("raw materials, commodities, processing, Africa exports, BACI")

  defp keywords("intra"),
    do: gettext("intra-African trade, AfCFTA, regional trade, Africa exports, BACI")

  defp answer(id, rows, median, doc, locale) do
    ranked = Enum.filter(rows, &is_number(&1.value))
    [a, b, c | _] = ranked ++ [nil, nil, nil]
    lead = leaders(id, [a, b, c], doc, locale)
    pct = &pct(&1, locale)

    case id do
      "dependence" ->
        gettext(
          "In %{year}, %{lead}. In half of African countries, the first product makes more than %{median} of exports of goods.",
          year: doc["year"],
          lead: lead,
          median: pct.(median)
        )

      "raw" ->
        gettext(
          "In %{year}, %{lead}. For half of African countries, raw or barely processed materials make more than %{median} of exports.",
          year: doc["year"],
          lead: lead,
          median: pct.(median)
        )

      "intra" ->
        gettext(
          "In %{year}, %{lead}. Half of African countries sell more than %{median} of their exports to the rest of Africa.",
          year: doc["year"],
          lead: lead,
          median: pct.(median)
        )
    end
  end

  defp leaders(_id, [nil | _], _doc, _locale), do: gettext("no figure is available")

  defp leaders("dependence", [a | rest], doc, locale) do
    gettext("%{country} depends most on one product: %{product}, %{share} of its exports",
      country: a.name,
      product: Trade.heading(doc, a.product, locale) |> lower(locale),
      share: pct(a.value, locale)
    ) <> others(rest, locale)
  end

  defp leaders("raw", [a | rest], _doc, locale) do
    gettext("raw materials make %{share} of the exports of %{country}",
      country: a.name,
      share: pct(a.value, locale)
    ) <> others(rest, locale)
  end

  defp leaders("intra", [a | rest], _doc, locale) do
    gettext("%{country} sells the largest share of its exports to Africa: %{share}",
      country: a.name,
      share: pct(a.value, locale)
    ) <> others(rest, locale)
  end

  defp others(rest, locale) do
    case Enum.reject(rest, &is_nil/1) do
      [] ->
        ""

      list ->
        gettext(", ahead of %{others}",
          others: Enum.map_join(list, ", ", &"#{&1.name} (#{pct(&1.value, locale)})")
        )
    end
  end

  # Product labels start with a capital; inside a sentence, lower case
  # (« pétrole brut »), as written elsewhere on the site.
  defp lower(text, locale), do: SyliAtlasWeb.AfricaTradeController.lower(text, locale)

  @doc false
  def pct(nil, _locale), do: "—"
  # Rounded to zero but not zero: written as below the smallest step shown.
  def pct(v, locale) when v < 0.05 and v > 0,
    do: "<\u00A0" <> SyliAtlasWeb.Format.number(0.1, 1, locale) <> "\u00A0%"

  def pct(v, locale) when v == 0, do: SyliAtlasWeb.Format.number(0.0, 1, locale) <> "\u00A0%"
  # A no-break space: the sign never goes alone to the next line.
  def pct(v, locale), do: SyliAtlasWeb.Format.number(v, 1, locale) <> "\u00A0%"

  defp faq(id, rows, median, doc, locale) do
    ranked = Enum.filter(rows, &is_number(&1.value))
    first = List.first(ranked)
    above = Enum.count(ranked, &(&1.value >= 50))

    [
      {question(id),
       if(first,
         do: answer(id, rows, median, doc, locale),
         else: gettext("No figure is available.")
       )},
      {gettext("How many African countries are above 50 %?"),
       ngettext(
         "%{count} country out of %{total}, in %{year}.",
         "%{count} countries out of %{total}, in %{year}.",
         above,
         total: length(ranked),
         year: doc["year"]
       )},
      {method_question(id), method_answer(id)}
    ]
  end

  defp method_question("dependence"), do: gettext("What is a « product » in this ranking?")
  defp method_question("raw"), do: gettext("What counts as a raw material?")
  defp method_question("intra"), do: gettext("Is informal cross-border trade counted?")

  @doc false
  def method_answer("dependence"),
    do:
      gettext(
        "A heading of the Harmonized System at 4 digits, such as « crude oil » (2709) or « cocoa beans » (1801). The share is the value of that heading divided by all the country's exports of goods, from CEPII's BACI, which reconciles what exporters and importers declare."
      )

  def method_answer("raw"),
    do:
      gettext(
        "The products the United Nations classify as primary goods (BEC rev. 5: crude oil, ores, beans, raw cotton…), plus gold, precious stones and unwrought metals such as copper cathodes, which the classification counts as processed. Syli Atlas groups them because they leave with little added value."
      )

  def method_answer("intra"),
    do:
      gettext(
        "No. BACI only covers trade declared to customs. Informal cross-border trade, large in West and East Africa, is not counted: the real share of trade with Africa is higher than shown."
      )

  # Filters ----------------------------------------------------------------------

  defp matches?(_row, ""), do: true

  defp matches?(row, q) do
    String.contains?(Area.normalize(row.name), Area.normalize(q)) or
      String.downcase(row.code) == String.downcase(q)
  end

  defp default_dir("name"), do: "asc"
  defp default_dir(_), do: "desc"

  defp sort_rows(rows, "name", dir) do
    sorted = Enum.sort_by(rows, &Area.normalize(&1.name))
    if dir == "desc", do: Enum.reverse(sorted), else: sorted
  end

  defp sort_rows(rows, "value", "asc") do
    {ranked, missing} = Enum.split_with(rows, &is_number(&1.value))
    Enum.reverse(ranked) ++ missing
  end

  defp sort_rows(rows, "value", _), do: rows
end
