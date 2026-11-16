defmodule SyliAtlasWeb.AfricaTradeController do
  @moduledoc """
  Africa's goods trade taken as a whole (`/fr/afrique/commerce`), the list
  of products (`/fr/afrique/produits`) and one page per product
  (`/fr/afrique/produits/cacao`), from SyliAtlas.AfricaTrade (CEPII, BACI).

  A product page adapts to its product: what Africa mainly sells puts its
  exporters, its clients and its place in the world first; what it mainly
  buys puts its importers and suppliers first; a product with a processing
  chain (cocoa, copper, cotton…) shows Africa's share in world exports at
  each step. Every sentence is written from the figures, never by hand.
  Each page has its file (`.csv`).
  """
  use SyliAtlasWeb, :controller

  alias SyliAtlas.{AfricaTrade, Geo}
  alias SyliAtlas.Geo.Area
  alias SyliAtlasWeb.{Export, Paths, Seo, TradeRankingController, TradeTopics}

  plug :put_layout, false

  # Africa ----------------------------------------------------------------------

  def africa(conn, _params) do
    locale = conn.assigns.locale
    doc = AfricaTrade.document()
    a = AfricaTrade.africa() || raise SyliAtlasWeb.NotFoundError
    countries = countries(locale)
    paths = SyliAtlas.Locales.each(&TradeTopics.africa_path/1)
    answer = africa_answer(a, doc, countries, locale)
    title = gettext("Africa's trade in %{year}: what it sells, what it buys", year: doc["year"])
    faq = africa_faq(a, doc, countries, locale)

    render(conn, :africa,
      page_title: title,
      seo:
        Seo.page(locale, paths, answer, %{
          json_ld: [
            Seo.breadcrumbs([
              {"Syli Atlas", Paths.home(locale)},
              {gettext("Africa's trade"), paths[locale]}
            ]),
            Seo.dataset(
              name: gettext("Goods trade of Africa"),
              description: answer,
              path: paths[locale],
              locale: locale,
              area: %{name: gettext("Africa")},
              temporal: "#{doc["history_source"]["first_year"]}/#{doc["year"]}",
              keywords:
                gettext(
                  "Africa exports, Africa imports, intra-African trade, commodities, trade partners, BACI"
                ),
              variables: [
                {gettext("Exports of goods"), "USD"},
                {gettext("Imports of goods"), "USD"},
                {gettext("Share of trade between African countries"), "%"}
              ],
              based_on: {"CEPII, BACI", doc["source"]["url"]},
              downloads: [{"text/csv", TradeTopics.africa_csv_path(locale)}]
            ),
            Seo.faq(faq)
          ]
        }),
      alternates: Seo.alternates_for_header(paths),
      title: title,
      answer: answer,
      doc: doc,
      a: a,
      countries: countries,
      history: africa_history(a),
      faq: faq,
      products: product_cards(locale)
    )
  end

  def africa_csv(conn, params) do
    locale = conn.assigns.locale
    doc = AfricaTrade.document()
    a = AfricaTrade.africa() || raise SyliAtlasWeb.NotFoundError
    countries = countries(locale)
    sep = Export.separator(params["sep"], locale)
    name = &country_name(countries, &1, locale)

    rows =
      for(
        r <- a["exporters"],
        do: [gettext("Exporter"), name.(r["code"]), r["code"], r["value"], r["share"]]
      ) ++
        for(
          r <- a["importers"],
          do: [gettext("Importer"), name.(r["code"]), r["code"], r["value"], r["share"]]
        ) ++
        for(
          r <- a["clients"],
          do: [
            gettext("Client outside Africa"),
            name.(r["code"]),
            r["code"],
            r["value"],
            r["share"]
          ]
        ) ++
        for(
          r <- a["suppliers"],
          do: [
            gettext("Supplier outside Africa"),
            name.(r["code"]),
            r["code"],
            r["value"],
            r["share"]
          ]
        ) ++
        for(
          r <- a["top_exports"],
          do: [
            gettext("Exported product"),
            AfricaTrade.heading(r["code"], locale),
            "HS " <> r["code"],
            r["value"],
            r["share"]
          ]
        ) ++
        for(
          r <- a["top_imports"],
          do: [
            gettext("Imported product"),
            AfricaTrade.heading(r["code"], locale),
            "HS " <> r["code"],
            r["value"],
            r["share"]
          ]
        ) ++
        for(
          {y, e, _i} <- africa_history(a),
          do: [gettext("Exports, year"), to_string(y), "", e, nil]
        ) ++
        for(
          {y, _e, i} <- africa_history(a),
          do: [gettext("Imports, year"), to_string(y), "", i, nil]
        )

    body =
      Export.csv_document(
        TradeRankingController.about(
          doc,
          gettext("Africa's trade"),
          TradeTopics.africa_path(locale)
        ),
        [
          gettext("Table"),
          gettext("Name"),
          gettext("Code"),
          gettext("Value (US dollars)"),
          gettext("Share (%)")
        ],
        rows,
        sep
      )

    TradeRankingController.send_csv(conn, "syli-atlas_africa-trade_#{doc["year"]}.csv", body)
  end

  # Products ----------------------------------------------------------------------

  def products(conn, _params) do
    locale = conn.assigns.locale
    doc = AfricaTrade.document()
    paths = SyliAtlas.Locales.each(&TradeTopics.products_path/1)
    cards = product_cards(locale)

    title =
      gettext("Africa's main products: who exports them, who buys them (%{year})",
        year: doc["year"]
      )

    answer =
      gettext(
        "%{count} products followed one by one: cocoa, gold, copper, crude oil, wheat… For each, the African countries that export or buy it, Africa's share in the world and its clients, from CEPII's BACI (%{year}).",
        count: length(cards),
        year: doc["year"]
      )

    render(conn, :products,
      page_title: title,
      seo:
        Seo.page(locale, paths, answer, %{
          json_ld: [
            Seo.breadcrumbs([
              {"Syli Atlas", Paths.home(locale)},
              {gettext("Africa's trade"), TradeTopics.africa_path(locale)},
              {gettext("Products"), paths[locale]}
            ]),
            Seo.item_list(title, for(c <- cards, do: {c.name, c.path}))
          ]
        }),
      alternates: Seo.alternates_for_header(paths),
      title: title,
      answer: answer,
      doc: doc,
      countries: countries(locale),
      groups:
        cards
        |> Enum.group_by(& &1.group)
        |> then(fn g -> for k <- [:farm, :energy, :mining, :bought], g[k], do: {k, g[k]} end)
    )
  end

  def product(conn, %{"slug" => slug}) do
    locale = conn.assigns.locale
    id = TradeTopics.product_id(slug) || raise SyliAtlasWeb.NotFoundError
    p = AfricaTrade.product(id) || raise SyliAtlasWeb.NotFoundError
    path = TradeTopics.product_path(locale, id)

    if conn.request_path != path do
      conn |> put_status(301) |> redirect(to: path)
    else
      render_product(conn, id, p, locale)
    end
  end

  defp render_product(conn, id, p, locale) do
    doc = AfricaTrade.document()
    countries = countries(locale)
    paths = SyliAtlas.Locales.each(&TradeTopics.product_path(&1, id))
    kind = AfricaTrade.kind(p)
    answer = product_answer(id, p, kind, doc, countries, locale)
    title = product_page_title(id, kind, doc["year"])
    faq = product_faq(id, p, kind, doc, countries, locale)
    group = TradeTopics.product_group(id)

    render(conn, :product,
      page_title: title,
      seo:
        Seo.page(locale, paths, answer, %{
          json_ld: [
            Seo.breadcrumbs([
              {"Syli Atlas", Paths.home(locale)},
              {gettext("Africa's trade"), TradeTopics.africa_path(locale)},
              {gettext("Products"), TradeTopics.products_path(locale)},
              {TradeTopics.product_name(id), paths[locale]}
            ]),
            Seo.dataset(
              name: TradeTopics.product_title(id),
              description: answer,
              path: paths[locale],
              locale: locale,
              area: %{name: gettext("Africa")},
              temporal: "#{doc["history_source"]["first_year"]}/#{doc["year"]}",
              keywords:
                Enum.join(
                  [
                    TradeTopics.product_name(id),
                    gettext("Africa"),
                    gettext("exports"),
                    gettext("imports")
                  ] ++
                    Enum.map(p["codes"], &"HS #{&1}"),
                  ", "
                ),
              variables: [
                {gettext("Exports of goods"), "USD"},
                {gettext("Imports of goods"), "USD"},
                {gettext("Share of Africa in world exports"), "%"}
              ],
              based_on: {"CEPII, BACI", doc["source"]["url"]},
              downloads: [{"text/csv", TradeTopics.product_csv_path(locale, id)}]
            ),
            Seo.faq(faq)
          ]
        }),
      alternates: Seo.alternates_for_header(paths),
      id: id,
      p: p,
      kind: kind,
      title: title,
      answer: answer,
      doc: doc,
      countries: countries,
      history: AfricaTrade.history(p),
      faq: faq,
      related:
        for(
          other <- AfricaTrade.products(),
          other != id,
          TradeTopics.product_group(other) == group,
          do: other
        ),
      companies: SyliAtlas.Companies.published(id)
    )
  end

  def product_csv(conn, params) do
    locale = conn.assigns.locale
    id = conn.assigns.product
    p = AfricaTrade.product(id) || raise SyliAtlasWeb.NotFoundError
    doc = AfricaTrade.document()
    countries = countries(locale)
    sep = Export.separator(params["sep"], locale)
    name = &country_name(countries, &1, locale)

    rows =
      for(
        r <- p["exporters"],
        do: [
          gettext("African exporter"),
          name.(r["code"]),
          r["code"],
          r["value"],
          r["share"],
          r["world_share"]
        ]
      ) ++
        for(
          r <- p["importers"],
          do: [
            gettext("African importer"),
            name.(r["code"]),
            r["code"],
            r["value"],
            r["share"],
            nil
          ]
        ) ++
        for(
          r <- p["world_top"],
          do: [
            gettext("World exporter"),
            name.(r["code"]),
            r["code"],
            r["value"],
            nil,
            r["share"]
          ]
        ) ++
        for(
          r <- p["clients"],
          do: [
            gettext("Client of Africa"),
            name.(r["code"]),
            r["code"],
            r["value"],
            r["share"],
            nil
          ]
        ) ++
        for(
          r <- p["suppliers"],
          do: [
            gettext("Supplier of Africa"),
            name.(r["code"]),
            r["code"],
            r["value"],
            r["share"],
            nil
          ]
        ) ++
        for(
          s <- p["chain"],
          do: [
            gettext("Processing step"),
            TradeTopics.step_label(s["codes"]),
            "HS " <> Enum.join(s["codes"], "+"),
            s["value"],
            nil,
            s["world_share"]
          ]
        ) ++
        for(
          {y, e, _i} <- AfricaTrade.history(p),
          do: [gettext("Exports, year"), to_string(y), "", e, nil, nil]
        ) ++
        for(
          {y, _e, i} <- AfricaTrade.history(p),
          do: [gettext("Imports, year"), to_string(y), "", i, nil, nil]
        )

    body =
      Export.csv_document(
        TradeRankingController.about(
          doc,
          TradeTopics.product_title(id) <> " (HS " <> Enum.join(p["codes"], ", ") <> ")",
          TradeTopics.product_path(locale, id)
        ),
        [
          gettext("Table"),
          gettext("Name"),
          gettext("Code"),
          gettext("Value (US dollars)"),
          gettext("Share of Africa (%)"),
          gettext("Share of the world (%)")
        ],
        rows,
        sep
      )

    TradeRankingController.send_csv(
      conn,
      "syli-atlas_" <> TradeTopics.product_slug(id, locale) <> "_#{doc["year"]}.csv",
      body
    )
  end

  # Countries -------------------------------------------------------------------

  @doc false
  def countries(locale) do
    Map.new(Geo.list_countries(), fn a ->
      {a.code, %{name: Area.name(a, locale), slug: Area.slug(a, locale), region: a.region_code}}
    end)
  end

  @doc false
  def country_name(countries, code, locale) do
    case countries[code] do
      %{name: name} -> name
      nil -> AfricaTrade.partner_name(code, locale)
    end
  end

  defp pct(v, locale), do: TradeRankingController.pct(v, locale)
  defp usd(v, locale), do: SyliAtlasWeb.WorldBankComponents.usd(v, locale)

  defp africa_history(a) do
    (a["history"] || %{})
    |> Enum.map(fn {y, v} -> {String.to_integer(y), v["exports"], v["imports"]} end)
    |> Enum.sort()
  end

  # Sentences --------------------------------------------------------------------

  defp africa_answer(a, doc, countries, locale) do
    [first, second | _] = a["top_exports"]
    [c1, c2 | _] = a["clients"]

    gettext(
      "In %{year}, the 54 African countries exported %{exports} of goods and imported %{imports}. %{first} comes first (%{first_share} of exports), ahead of %{second} (%{second_share}). %{intra} of exports go to other African countries; outside Africa, the first clients are %{c1} (%{c1_share}) and %{c2} (%{c2_share}).",
      year: doc["year"],
      exports: usd(a["exports"], locale),
      imports: usd(a["imports"], locale),
      first: AfricaTrade.heading(first["code"], locale),
      first_share: pct(first["share"], locale),
      second: lower(AfricaTrade.heading(second["code"], locale), locale),
      second_share: pct(second["share"], locale),
      intra: pct(a["intra_share"], locale),
      c1: country_name(countries, c1["code"], locale),
      c1_share: pct(c1["share"], locale),
      c2: country_name(countries, c2["code"], locale),
      c2_share: pct(c2["share"], locale)
    )
  end

  @doc false
  def lower(text, locale) when locale in ["fr", "en", "es", "pt"] do
    {first, rest} = String.split_at(text, 1)
    String.downcase(first) <> rest
  end

  def lower(text, _locale), do: text

  defp africa_faq(a, doc, countries, locale) do
    [e1, e2, e3 | _] = a["exporters"]
    [s1 | _] = a["suppliers"]
    raw = SyliAtlas.Trade.raw_share(a["stages"]["exports"])
    raw_imports = SyliAtlas.Trade.raw_share(a["stages"]["imports"])

    [
      {gettext("What does Africa export the most?"),
       gettext(
         "%{first}, %{share} of the exports of goods in %{year}, then %{others}. Raw or barely processed materials make %{raw} of what Africa sells, against %{raw_imports} of what it buys.",
         first: AfricaTrade.heading(hd(a["top_exports"])["code"], locale),
         share: pct(hd(a["top_exports"])["share"], locale),
         others:
           a["top_exports"]
           |> Enum.slice(1, 3)
           |> Enum.map_join(", ", &lower(AfricaTrade.heading(&1["code"], locale), locale)),
         year: doc["year"],
         raw: pct(raw, locale),
         raw_imports: pct(raw_imports, locale)
       )},
      {gettext("Which African countries export the most?"),
       gettext("%{c1} (%{v1}), %{c2} (%{v2}) and %{c3} (%{v3}) in %{year}.",
         c1: country_name(countries, e1["code"], locale),
         v1: usd(e1["value"], locale),
         c2: country_name(countries, e2["code"], locale),
         v2: usd(e2["value"], locale),
         c3: country_name(countries, e3["code"], locale),
         v3: usd(e3["value"], locale),
         year: doc["year"]
       )},
      {gettext("How much do African countries trade with each other?"),
       gettext(
         "%{share} of African exports went to other African countries in %{year} (%{value}). This only counts trade declared to customs: informal cross-border trade is not included.",
         share: pct(a["intra_share"], locale),
         value: usd(a["intra"], locale),
         year: doc["year"]
       )},
      {gettext("Where do Africa's imports come from?"),
       gettext(
         "Outside Africa, %{s1} comes first with %{s1_share} of African imports in %{year}.",
         s1: country_name(countries, s1["code"], locale),
         s1_share: pct(s1["share"], locale),
         year: doc["year"]
       )}
    ]
  end

  @doc false
  def product_page_title(id, :export, year),
    do:
      gettext("%{title}: exporters, clients and share of the world (%{year})",
        title: TradeTopics.product_title(id),
        year: year
      )

  def product_page_title(id, :import, year),
    do:
      gettext("%{title}: importers, suppliers and African producers (%{year})",
        title: TradeTopics.product_title(id),
        year: year
      )

  @doc false
  def product_answer(id, p, :export, doc, countries, locale) do
    [e1 | rest] = p["exporters"]
    e2 = List.first(rest)

    gettext(
      "%{product}: in %{year}, Africa exported %{value} worth, %{share} of world exports.",
      product: TradeTopics.product_name(id),
      year: doc["year"],
      value: usd(p["exports"], locale),
      share: pct(p["world_share"], locale)
    ) <>
      " " <>
      if(e2,
        do:
          gettext("%{c1} supplies %{s1} of African exports, %{c2} %{s2}.",
            c1: country_name(countries, e1["code"], locale),
            s1: pct(e1["share"], locale),
            c2: country_name(countries, e2["code"], locale),
            s2: pct(e2["share"], locale)
          ),
        else:
          gettext("%{c1} supplies %{s1} of African exports.",
            c1: country_name(countries, e1["code"], locale),
            s1: pct(e1["share"], locale)
          )
      )
  end

  def product_answer(id, p, :import, doc, countries, locale) do
    [i1 | _] = p["importers"]

    gettext(
      "%{product}: in %{year}, Africa bought %{imports} worth and sold %{exports} worth. %{c1} makes %{s1} of African purchases; %{intra} of what Africa buys comes from other African countries.",
      product: TradeTopics.product_name(id),
      year: doc["year"],
      imports: usd(p["imports"], locale),
      exports: usd(p["exports"], locale),
      c1: country_name(countries, i1["code"], locale),
      s1: pct(i1["share"], locale),
      intra: pct(p["imports_from_africa"], locale)
    )
  end

  defp product_faq(id, p, kind, doc, countries, locale) do
    name = TradeTopics.product_name(id)
    hist = AfricaTrade.history(p)

    first =
      case kind do
        :export ->
          [e1 | _] = p["exporters"]

          {gettext("%{product}: which African country exports the most?", product: name),
           gettext(
             "%{country}: %{value} in %{year}, %{share} of African exports and %{world} of world exports.",
             country: country_name(countries, e1["code"], locale),
             value: usd(e1["value"], locale),
             year: doc["year"],
             share: pct(e1["share"], locale),
             world: pct(e1["world_share"], locale)
           )}

        :import ->
          [i1 | _] = p["importers"]

          {gettext("%{product}: which African country buys the most?", product: name),
           gettext("%{country}: %{value} in %{year}, %{share} of African purchases.",
             country: country_name(countries, i1["code"], locale),
             value: usd(i1["value"], locale),
             year: doc["year"],
             share: pct(i1["share"], locale)
           )}
      end

    world =
      case p["world_top"] do
        [w1 | _] ->
          [
            {gettext("%{product}: who exports the most in the world?", product: name),
             gettext("%{country}, with %{share} of world exports in %{year}.",
               country: country_name(countries, w1["code"], locale),
               share: pct(w1["share"], locale),
               year: doc["year"]
             )}
          ]

        _ ->
          []
      end

    clients =
      case {kind, p["clients"], p["suppliers"]} do
        {:export, [c1, c2 | _], _} ->
          [
            {gettext("%{product}: who buys it from Africa?", product: name),
             gettext("First %{c1} (%{s1} in %{year}), then %{c2} (%{s2}).",
               c1: country_name(countries, c1["code"], locale),
               s1: pct(c1["share"], locale),
               c2: country_name(countries, c2["code"], locale),
               s2: pct(c2["share"], locale),
               year: doc["year"]
             )}
          ]

        {:import, _, [s1, s2 | _]} ->
          [
            {gettext("%{product}: where does Africa buy it?", product: name),
             gettext("First from %{c1} (%{s1} in %{year}), then from %{c2} (%{s2}).",
               c1: country_name(countries, s1["code"], locale),
               s1: pct(s1["share"], locale),
               c2: country_name(countries, s2["code"], locale),
               s2: pct(s2["share"], locale),
               year: doc["year"]
             )}
          ]

        _ ->
          []
      end

    trend =
      case {List.first(hist), List.last(hist)} do
        {{y0, e0, i0}, {y1, e1, i1}} ->
          {v0, v1} = if kind == :export, do: {e0, e1}, else: {i0, i1}

          [
            {gettext("%{product}: how has trade changed since %{year}?", product: name, year: y0),
             if(kind == :export,
               do:
                 gettext("African exports went from %{v0} in %{y0} to %{v1} in %{y1}.",
                   v0: usd(v0, locale),
                   v1: usd(v1, locale),
                   y0: y0,
                   y1: y1
                 ),
               else:
                 gettext("African purchases went from %{v0} in %{y0} to %{v1} in %{y1}.",
                   v0: usd(v0, locale),
                   v1: usd(v1, locale),
                   y0: y0,
                   y1: y1
                 )
             )}
          ]

        _ ->
          []
      end

    [first] ++ world ++ clients ++ trend
  end

  # Cards of the products' index (also on the Africa page).
  defp product_cards(locale) do
    for id <- AfricaTrade.products(), p = AfricaTrade.product(id) do
      kind = AfricaTrade.kind(p)
      lead = if kind == :export, do: List.first(p["exporters"]), else: List.first(p["importers"])

      %{
        id: id,
        name: TradeTopics.product_name(id),
        path: TradeTopics.product_path(locale, id),
        group: TradeTopics.product_group(id),
        kind: kind,
        value: if(kind == :export, do: p["exports"], else: p["imports"]),
        world_share: p["world_share"],
        lead: lead && lead["code"],
        lead_share: lead && lead["share"]
      }
    end
  end
end
