defmodule SyliAtlasWeb.TradeDetailComponents do
  @moduledoc """
  The detailed blocks of a country's Trade tab, under the headline section
  (`SyliAtlasWeb.TradeComponents`): products and their buyers, stage of
  processing, exports since 1995, trade with the rest of Africa, the
  "African potential", trade in services and logistics, and the questions
  of the tab.

  Every block names its source; what Syli Atlas calculates says so.
  Everything is rendered on the server: no JavaScript, readable offline and
  by search engines.
  """
  use Phoenix.Component
  use Gettext, backend: SyliAtlasWeb.Gettext

  import SyliAtlasWeb.UI
  import SyliAtlasWeb.Format, only: [number: 3, names: 2]
  alias SyliAtlas.Trade
  alias SyliAtlasWeb.{Paths, TradeComponents, WorldBankComponents}

  attr :entry, :map, required: true
  attr :doc, :map, required: true
  attr :name, :string, required: true
  attr :locale, :string, required: true
  attr :slugs, :map, default: %{}, doc: "code => {name, slug} of the African countries"
  attr :communities, :list, default: []
  attr :world_bank, :any, default: nil

  @doc "All the detailed blocks, in page order."
  def details(assigns) do
    ~H"""
    <.products_section entry={@entry} doc={@doc} name={@name} locale={@locale} />
    <.stages_section entry={@entry} doc={@doc} name={@name} locale={@locale} />
    <.history_section entry={@entry} doc={@doc} name={@name} locale={@locale} />
    <.africa_section
      entry={@entry}
      doc={@doc}
      name={@name}
      locale={@locale}
      slugs={@slugs}
      communities={@communities}
    />
    <.potential_section entry={@entry} doc={@doc} name={@name} locale={@locale} slugs={@slugs} />
    <.services_section world_bank={@world_bank} name={@name} locale={@locale} />
    """
  end

  # Products ---------------------------------------------------------------

  attr :entry, :map, required: true
  attr :doc, :map, required: true
  attr :name, :string, required: true
  attr :locale, :string, required: true

  def products_section(assigns) do
    products = assigns.entry["top_products"] || []

    assigns =
      assign(assigns,
        products: products,
        max: (List.first(products) || %{"share" => 1})["share"] || 1
      )

    ~H"""
    <.section :if={@products != []} id="produits" variant="alt">
      <.section_head
        eyebrow={gettext("Products")}
        title={gettext("What %{name} sells, product by product", names(@name, []))}
      >
        <:intro>
          {gettext(
            "Main exported products in %{year} (HS 4-digit headings), and who buys each of them. %{count} products were exported, %{over} of them for more than one million dollars.",
            year: @doc["year"],
            count: number(@entry["products_exported"], 0, @locale),
            over: number(@entry["products_over_1m"], 0, @locale)
          )}
        </:intro>
      </.section_head>
      <.card pad class="stack gap-3" id="top-products">
        <ul class="share-list">
          <li :for={p <- @products}>
            <a
              :if={page = SyliAtlas.AfricaTrade.product_of_heading(p["code"])}
              href={SyliAtlasWeb.TradeTopics.product_path(@locale, page)}
            >{Trade.heading(@doc, p["code"], @locale)}</a>
            <span :if={!SyliAtlas.AfricaTrade.product_of_heading(p["code"])}>
              {Trade.heading(@doc, p["code"], @locale)}
            </span>
            <span class="share-track">
              <span style={"width: #{width(p["share"], @max)}%"}></span>
            </span>
            <b class="num">{pct(p["share"], @locale)}</b>
          </li>
        </ul>
        <div class="stack gap-2" id="product-buyers">
          <details :for={p <- @products} class="faq">
            <summary>
              {gettext("Who buys it: %{product}", product: Trade.heading(@doc, p["code"], @locale))}
            </summary>
            <p>
              <span class="muted">{WorldBankComponents.usd(p["value"], @locale)} · HS {p["code"]} ·</span>
              {Enum.map_join(
                p["clients"],
                ", ",
                &"#{TradeComponents.partner(@doc, &1["code"], @locale)} #{pct(&1["share"], @locale)}"
              )}
            </p>
          </details>
        </div>
        <p class="src">
          {gettext(
            "Source: CEPII, BACI (version %{version}), Licence Ouverte Etalab 2.0 · headings and buyers of each product: Syli Atlas calculation",
            version: @doc["source"]["version"]
          )}
        </p>
      </.card>
    </.section>
    """
  end

  # Stage of processing ----------------------------------------------------

  attr :entry, :map, required: true
  attr :doc, :map, required: true
  attr :name, :string, required: true
  attr :locale, :string, required: true

  def stages_section(assigns) do
    stages = assigns.entry["stages"]

    assigns =
      assign(assigns,
        stages: stages,
        median: assigns.doc["medians"]["raw_share_exports"],
        raw: stages && SyliAtlas.Trade.raw_share(stages["exports"]),
        raw_imports: stages && SyliAtlas.Trade.raw_share(stages["imports"]),
        rows:
          stages &&
            [
              {gettext("Exports"), stages["exports"], "stage-exports"},
              {gettext("Imports"), stages["imports"], "stage-imports"}
            ]
      )

    ~H"""
    <.section :if={@stages} id="transformation">
      <.section_head
        eyebrow={gettext("Raw or processed")}
        title={stage_title(@raw)}
      >
        <:intro>
          {gettext(
            "%{primary} of the exports %{of_name} are raw materials, unprocessed or barely processed: farm produce, ores, oil, gold, unwrought metals (African median: %{median}). They make up %{imports} of its imports.",
            names(@name,
              primary: pct(@raw, @locale),
              median: pct(@median, @locale),
              imports: pct(@raw_imports, @locale)
            )
          )}
        </:intro>
      </.section_head>
      <.card pad class="stack gap-4" id="stages">
        <div :for={{label, s, id} <- @rows} class="stack gap-2" id={id}>
          <b>{label}</b>
          <div
            class="stacked-bar stacked-bar-lg"
            role="img"
            aria-label={stage_label(label, s, @locale)}
          >
            <span
              :for={{k, color} <- stage_parts()}
              style={"flex: #{s[k] || 0}; background: var(#{color})"}
            ></span>
          </div>
          <ul class="legend share-legend">
            <li :for={{k, color} <- stage_parts()} style={"--dot: var(#{color})"}>
              <i aria-hidden="true"></i>{stage_name(k)} {pct(s[k], @locale)}
            </li>
          </ul>
        </div>
        <p class="src">
          {gettext(
            "Stage of processing: United Nations, correspondence between HS 2022 and the Broad Economic Categories (BEC rev. 5), applied to CEPII BACI by Syli Atlas. The BEC counts gold, precious stones and unwrought metals (copper cathodes, cobalt…) as processed goods: Syli Atlas shows them apart, as barely processed raw materials. Final goods: consumption and equipment. The rest of the trade is not classified."
          )}
        </p>
      </.card>
    </.section>
    """
  end

  defp stage_parts,
    do: [{"primary", "--c2"}, {"unwrought", "--c5"}, {"intermediate", "--c3"}, {"final", "--c1"}]

  defp stage_name("primary"), do: gettext("Primary (raw)")
  defp stage_name("unwrought"), do: gettext("Gold, precious stones, unwrought metals")
  defp stage_name("intermediate"), do: gettext("Processed intermediate goods")
  defp stage_name("final"), do: gettext("Final goods (consumption, equipment)")

  defp stage_label(label, s, locale),
    do:
      label <>
        " : " <>
        Enum.map_join(stage_parts(), ", ", fn {k, _} ->
          "#{stage_name(k)} #{pct(s[k], locale)}"
        end)

  defp stage_title(p) when is_number(p) and p >= 60,
    do: gettext("Mostly raw goods sold, processed goods bought")

  defp stage_title(p) when is_number(p) and p >= 30, do: gettext("Raw and processed goods sold")
  defp stage_title(_), do: gettext("Mostly processed goods sold")

  # Exports since 1995 -----------------------------------------------------

  attr :entry, :map, required: true
  attr :doc, :map, required: true
  attr :name, :string, required: true
  attr :locale, :string, required: true

  def history_section(assigns) do
    points = Trade.history(assigns.entry)
    chapter = List.first(assigns.entry["top_exports"] || [])
    shares = get_in(assigns.entry, ["history", "first_chapter_share"]) || %{}

    assigns =
      assign(assigns,
        points: points,
        shares: shares,
        chapter:
          chapter && TradeComponents.chapter(assigns.doc, chapter["chapter"], assigns.locale),
        chart: if(length(points) > 2, do: chart(points))
      )

    ~H"""
    <.section :if={@chart} id="historique">
      <.section_head
        eyebrow={gettext("Since %{year}", year: elem(hd(@points), 0))}
        title={gettext("%{years} years of exports", years: length(@points))}
      >
        <:intro>{history_lead(@points, @shares, @chapter, @locale)}</:intro>
      </.section_head>
      <.card pad class="stack gap-3" id="exports-history">
        <svg
          class="chart"
          viewBox="0 0 760 260"
          role="img"
          aria-label={history_label(@points, @locale)}
        >
          <line :for={t <- @chart.ticks} class="grid-line" x1="64" x2="740" y1={t.y} y2={t.y}></line>
          <text :for={t <- @chart.ticks} x="56" y={t.y + 4} text-anchor="end">
            {tick(t.v, @locale)}
          </text>
          <text :for={{y, x} <- @chart.years} x={x} y="252" text-anchor="middle">{y}</text>
          <path d={@chart.area} style="fill: var(--accent-bg)"></path>
          <path class="series" d={@chart.line} style="stroke: var(--c1); stroke-width: 3"></path>
          <circle cx={@chart.last.x} cy={@chart.last.y} r="5" style="fill: var(--c1)"></circle>
        </svg>
        <details class="chart-data" id="exports-history-data">
          <summary>{gettext("Chart data as a table")}</summary>
          <div class="table-box" role="region" aria-labelledby="exports-history-caption" tabindex="0">
            <table class="table">
              <caption id="exports-history-caption">
                {gettext("Exports of goods, %{y0}–%{y1}, in US dollars",
                  y0: elem(hd(@points), 0),
                  y1: elem(List.last(@points), 0)
                )}
              </caption>
              <thead>
                <tr>
                  <th scope="col" class="l">{gettext("Year")}</th>
                  <th scope="col">{gettext("Exports of goods")}</th>
                  <th :if={@chapter} scope="col">{@chapter}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={{y, v} <- @points}>
                  <th scope="row" class="l">{y}</th>
                  <td>{WorldBankComponents.usd(v, @locale)}</td>
                  <td :if={@chapter}>{pct(@shares[to_string(y)], @locale)}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </details>
        <p class="src">
          {gettext(
            "Source: CEPII, BACI, HS 1992 nomenclature (version %{version}), Licence Ouverte Etalab 2.0. The 1992 nomenclature covers the whole period; its recent totals differ slightly from those above (HS 2022).",
            version: get_in(@doc, ["history_source", "version"]) || @doc["source"]["version"]
          )}
        </p>
      </.card>
    </.section>
    """
  end

  defp history_lead(points, shares, chapter, locale) do
    {y0, v0} = hd(points)
    {y1, v1} = List.last(points)
    {ypeak, vpeak} = Enum.max_by(points, &elem(&1, 1))

    base =
      gettext(
        "Exports went from %{start} in %{y0} to %{end} in %{y1}; their peak was %{peak} in %{ypeak}.",
        start: WorldBankComponents.usd(v0, locale),
        y0: y0,
        end: WorldBankComponents.usd(v1, locale),
        y1: y1,
        peak: WorldBankComponents.usd(vpeak, locale),
        ypeak: ypeak
      )

    case {chapter, shares[to_string(y0)], shares[to_string(y1)]} do
      {c, a, b} when is_binary(c) and is_number(a) and is_number(b) ->
        base <>
          " " <>
          gettext("%{chapter} made up %{a} of them in %{y0} and %{b} in %{y1}.",
            chapter: c,
            a: pct(a, locale),
            b: pct(b, locale),
            y0: y0,
            y1: y1
          )

      _ ->
        base
    end
  end

  defp history_label(points, locale) do
    {y0, _} = hd(points)
    {y1, _} = List.last(points)

    gettext("Exports of goods, %{y0}–%{y1}, in US dollars", y0: y0, y1: y1) <>
      " : " <>
      Enum.map_join(points, ", ", fn {y, v} -> "#{y} #{WorldBankComponents.usd(v, locale)}" end)
  end

  @doc false
  def chart(points) do
    {x0, x1, y0, y1} = {64, 740, 230, 16}
    {first, _} = hd(points)
    {last, _} = List.last(points)
    max = points |> Enum.map(&elem(&1, 1)) |> Enum.max()
    step = nice_step(max / 4)
    top = step * (Float.ceil(max / step) |> trunc())
    top = if top == 0, do: 1, else: top
    span = max(last - first, 1)

    x = fn year -> Float.round(x0 + (x1 - x0) * (year - first) / span, 1) end
    y = fn v -> Float.round(y0 - (y0 - y1) * v / top, 1) end

    coords = for {yr, v} <- points, do: {x.(yr), y.(v)}

    line =
      coords
      |> Enum.with_index()
      |> Enum.map_join(" ", fn {{px, py}, i} -> "#{if i == 0, do: "M", else: "L"}#{px} #{py}" end)

    {lx, ly} = List.last(coords)
    {fx, _} = hd(coords)

    %{
      line: line,
      area: "#{line} L#{lx} #{y0} L#{fx} #{y0} Z",
      last: %{x: lx, y: ly},
      ticks: for(i <- 0..trunc(top / step), do: %{v: i * step, y: y.(i * step)}),
      years:
        for(yr <- first..last, rem(yr - first, 5) == 0 or yr == last, do: {yr, x.(yr)})
        |> Enum.uniq_by(&elem(&1, 0))
        |> drop_crowded()
    }
  end

  # The last year label is dropped when it would overlap the one before.
  defp drop_crowded(years) do
    case Enum.reverse(years) do
      [{_, xa}, {_, xb} | _] = rev when xa - xb < 40 ->
        Enum.reverse([hd(rev) | tl(tl(rev))])

      _ ->
        years
    end
  end

  defp nice_step(raw) when raw <= 0, do: 1

  defp nice_step(raw) do
    mag = :math.pow(10, Float.floor(:math.log10(raw)))

    Enum.find([1, 2, 2.5, 5, 10], &(&1 * mag >= raw))
    |> Kernel.*(mag)
  end

  defp tick(v, locale) when v >= 1.0e9,
    do:
      number(v / 1.0e9, if(v / 1.0e9 == trunc(v / 1.0e9), do: 0, else: 1), locale) <>
        " " <> SyliAtlasWeb.Format.billions(locale)

  defp tick(v, _locale) when v == 0, do: "0"
  defp tick(v, locale), do: WorldBankComponents.usd(v, locale)

  # Africa -----------------------------------------------------------------

  attr :entry, :map, required: true
  attr :doc, :map, required: true
  attr :name, :string, required: true
  attr :locale, :string, required: true
  attr :slugs, :map, default: %{}
  attr :communities, :list, default: []

  def africa_section(assigns) do
    partners = assigns.entry["africa_partners"] || []

    assigns =
      assign(assigns,
        partners: partners,
        shares: Trade.community_shares(assigns.entry, assigns.communities)
      )

    ~H"""
    <.section :if={@partners != []} id="afrique" variant="alt">
      <.section_head
        eyebrow={gettext("Africa")}
        title={gettext("Trade with the rest of Africa")}
      >
        <:intro>
          {gettext(
            "%{exports} of the exports %{of_name} go to other African countries, %{imports} of its imports come from them (%{year}).",
            names(@name,
              exports: pct(@entry["africa_share_exports"], @locale),
              imports: pct(@entry["africa_share_imports"], @locale),
              year: @doc["year"]
            )
          )}
        </:intro>
      </.section_head>
      <.card id="africa-partners">
        <.data_table
          id="africa-partners-table"
          caption={gettext("Main African partners")}
          rows={@partners}
        >
          <:head :let={p} label={gettext("African partner")}>
            <.partner_link code={p["code"]} doc={@doc} slugs={@slugs} locale={@locale} />
          </:head>
          <:col :let={p} label={gettext("Exports to")}>
            {WorldBankComponents.usd(p["exports"], @locale)}
          </:col>
          <:col :let={p} label={gettext("Imports from")}>
            {WorldBankComponents.usd(p["imports"], @locale)}
          </:col>
          <:col :let={p} label={gettext("First product sold")} class="l">
            {p["product"] && Trade.heading(@doc, p["product"], @locale)}
          </:col>
        </.data_table>
        <.card_foot>
          <span :if={@shares != []} class="stack gap-2">
            <span>{gettext("Share of trade with the members of each community:")}</span>
            <span class="row gap-1">
              <a
                :for={{c, e, i} <- @shares}
                class="pill pill-neutral"
                style="white-space: normal"
                href={Paths.community(@locale, SyliAtlas.Locales.pick(c.slug, @locale))}
              >
                {SyliAtlas.Locales.pick(c.short, @locale)} · {gettext("exports %{e}, imports %{i}",
                  e: pct(e, @locale),
                  i: pct(i, @locale)
                )}
              </a>
            </span>
          </span>
          <span>
            {gettext(
              "Source: CEPII, BACI (version %{version}) · trade by partner and by community: Syli Atlas calculation",
              version: @doc["source"]["version"]
            )}
          </span>
        </.card_foot>
      </.card>
    </.section>
    """
  end

  attr :code, :string, required: true
  attr :doc, :map, required: true
  attr :slugs, :map, required: true
  attr :locale, :string, required: true
  attr :tab, :atom, default: :trade

  defp partner_link(assigns) do
    assigns = assign(assigns, :entry, assigns.slugs[assigns.code])

    ~H"""
    <a :if={@entry} href={Paths.country_tab(@locale, elem(@entry, 1), @tab)}>{elem(@entry, 0)}</a>
    <span :if={!@entry}>{TradeComponents.partner(@doc, @code, @locale)}</span>
    """
  end

  attr :codes, :list, required: true
  attr :doc, :map, required: true
  attr :slugs, :map, required: true
  attr :locale, :string, required: true

  # Comma-separated links, with no space before the commas.
  defp partner_links(assigns) do
    last = length(assigns.codes) - 1

    assigns =
      assign(assigns,
        items:
          for {code, i} <- Enum.with_index(assigns.codes) do
            entry = assigns.slugs[code]

            %{
              href: entry && Paths.country_tab(assigns.locale, elem(entry, 1), :trade),
              name:
                if(entry,
                  do: elem(entry, 0),
                  else: TradeComponents.partner(assigns.doc, code, assigns.locale)
                ),
              sep: if(i < last, do: ", ", else: "")
            }
          end
      )

    ~H"""
    <%= for i <- @items do %>
      <a :if={i.href} href={i.href}>{i.name}</a><span :if={!i.href}>{i.name}</span>{i.sep}
    <% end %>
    """
  end

  # African potential ------------------------------------------------------

  attr :entry, :map, required: true
  attr :doc, :map, required: true
  attr :name, :string, required: true
  attr :locale, :string, required: true
  attr :slugs, :map, default: %{}

  def potential_section(assigns) do
    assigns = assign(assigns, :rows, assigns.entry["potential"] || [])

    ~H"""
    <.section :if={@rows != []} id="potentiel-africain">
      <.section_head
        eyebrow={gettext("African potential")}
        title={gettext("Bought outside Africa, made in Africa")}
      >
        <:intro>
          {gettext(
            "Products %{name} buys outside the continent while other African countries already export at least as much of them to the world (%{year}). An indication of where trade within Africa could grow, not a forecast.",
            names(@name, year: @doc["year"])
          )}
        </:intro>
      </.section_head>
      <.card id="african-potential">
        <.data_table id="african-potential-table" caption={gettext("African potential")} rows={@rows}>
          <:head :let={r} label={gettext("Product bought")}>
            {Trade.heading(@doc, r["code"], @locale)}
          </:head>
          <:col :let={r} label={gettext("Bought outside Africa")}>
            <b>{WorldBankComponents.usd(r["value"], @locale)}</b>
          </:col>
          <:col :let={r} label={gettext("First supplier")} class="l">
            {TradeComponents.partner(@doc, r["supplier"], @locale)}
          </:col>
          <:col :let={r} label={gettext("African exporters")} class="l">
            <.partner_links codes={r["exporters"]} doc={@doc} slugs={@slugs} locale={@locale} />
          </:col>
        </.data_table>
        <.card_foot>
          {gettext(
            "Syli Atlas calculation on CEPII BACI: imports from outside Africa of each HS 6-digit product above one million dollars, kept when the other African countries export at least as much of it, and at least five million dollars, to the world. Prices, quality and transport are not taken into account."
          )}
        </.card_foot>
      </.card>
    </.section>
    """
  end

  # Services and logistics -------------------------------------------------

  attr :world_bank, :any, default: nil
  attr :name, :string, required: true
  attr :locale, :string, required: true

  def services_section(assigns) do
    l = (assigns.world_bank && assigns.world_bank["latest"]) || %{}

    assigns =
      assign(assigns,
        services: l["services_exports_usd"],
        tourism: l["tourism_receipts_usd"],
        lpi: l["lpi"]
      )

    ~H"""
    <.section id="services-logistique">
      <.section_head
        eyebrow={gettext("Beyond goods")}
        title={gettext("Services, tourism and logistics")}
      />
      <.stat_grid
        :if={@services || @tourism || @lpi}
        class={if(Enum.count([@services, @tourism, @lpi], & &1) == 3, do: "stats-3")}
      >
        <:stat
          :if={@services}
          id="services-exports"
          label={gettext("Exports of services · %{year}", year: @services["year"])}
          value={WorldBankComponents.money_usd(@services["value"], @services["year"], @locale)}
        >
          {gettext("transport, travel, telecoms… · IMF via the World Bank")}
        </:stat>
        <:stat
          :if={@tourism}
          id="tourism-receipts"
          label={gettext("Tourism receipts · %{year}", year: @tourism["year"])}
          value={WorldBankComponents.money_usd(@tourism["value"], @tourism["year"], @locale)}
        >
          {gettext("UN Tourism via the World Bank")}
        </:stat>
        <:stat
          :if={@lpi}
          id="lpi"
          label={gettext("Logistics performance · %{year}", year: @lpi["year"])}
          value={number(@lpi["value"], 2, @locale) <> " / 5"}
        >
          {gettext("World Bank Logistics Performance Index (1 = low, 5 = high)")}
        </:stat>
      </.stat_grid>
      <p class="src">
        {gettext(
          "Source: World Bank, World Development Indicators, CC BY 4.0. Customs figures (BACI) count only declared trade: informal trade across land borders, large in many African countries, is not in them."
        )}
      </p>
    </.section>
    """
  end

  # Questions --------------------------------------------------------------

  @doc "Questions and answers of the Trade tab, shown on the page and as FAQPage."
  def faq_items(_name, nil, _doc, _locale), do: []

  def faq_items(name, e, doc, locale) do
    year = doc["year"]
    products = e["top_products"] || []
    primary = Trade.raw_share(get_in(e, ["stages", "exports"]))

    [
      products != [] &&
        {gettext("What does %{name} export?", names(name, [])),
         gettext(
           "Main exports in %{year}: %{list} (shares of goods exports, CEPII, BACI).",
           year: year,
           list:
             products
             |> Enum.take(3)
             |> Enum.map_join(
               ", ",
               &"#{lower(Trade.heading(doc, &1["code"], locale))} (#{pct(&1["share"], locale)})"
             )
         )},
      e["top_clients"] != [] &&
        {gettext("Who buys the exports of %{name}?", names(name, [])),
         gettext("Main clients in %{year}: %{list} (shares of goods exports).",
           year: year,
           list:
             e["top_clients"]
             |> Enum.take(3)
             |> Enum.map_join(
               ", ",
               &"#{TradeComponents.partner(doc, &1["code"], locale)} (#{pct(&1["share"], locale)})"
             )
         )},
      primary &&
        {gettext("Does %{name} export raw materials?", names(name, [])),
         gettext(
           "%{primary} of its exports are raw materials, unprocessed or barely processed (farm produce, ores, oil, gold, unwrought metals), against an African median of %{median} (%{year}).",
           primary: pct(primary, locale),
           median: pct(doc["medians"]["raw_share_exports"], locale),
           year: year
         )},
      {gettext("How much does %{name} trade with the rest of Africa?", names(name, [])),
       gettext(
         "%{exports} of its exports go to other African countries and %{imports} of its imports come from them (%{year}).",
         exports: pct(e["africa_share_exports"], locale),
         imports: pct(e["africa_share_imports"], locale),
         year: year
       )},
      (e["potential"] || []) != [] &&
        {gettext("What does %{name} buy outside Africa that Africa produces?", names(name, [])),
         gettext(
           "Mainly %{list}: other African countries already export at least as much of them (Syli Atlas calculation on BACI, %{year}).",
           year: year,
           list:
             e["potential"]
             |> Enum.take(3)
             |> Enum.map_join(
               ", ",
               &"#{lower(Trade.heading(doc, &1["code"], locale))} (#{WorldBankComponents.usd(&1["value"], locale)})"
             )
         )}
    ]
    |> Enum.filter(& &1)
  end

  # Helpers ----------------------------------------------------------------

  defp width(v, max) when is_number(v) and max > 0, do: Float.round(min(100.0, 100 * v / max), 1)
  defp width(_, _), do: 0

  defp lower(nil), do: ""
  defp lower(text), do: String.downcase(String.first(text)) <> String.slice(text, 1..-1//1)

  defp pct(nil, _), do: "—"
  defp pct(v, locale), do: number(v, 1, locale) <> " %"
end
