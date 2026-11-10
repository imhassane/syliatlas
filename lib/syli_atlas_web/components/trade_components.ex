defmodule SyliAtlasWeb.TradeComponents do
  @moduledoc "The trade section of a country profile (`SyliAtlas.Trade`)."
  use Phoenix.Component
  use Gettext, backend: SyliAtlasWeb.Gettext

  import SyliAtlasWeb.UI
  import SyliAtlasWeb.Format, only: [number: 3]
  alias SyliAtlasWeb.WorldBankComponents

  attr :entry, :map, required: true
  attr :doc, :map, required: true
  attr :name, :string, required: true
  attr :locale, :string, required: true

  def trade_section(assigns) do
    e = assigns.entry
    doc = assigns.doc
    top = List.first(e["top_exports"])

    assigns =
      assign(assigns,
        top: top,
        top_label: top && chapter(doc, top["chapter"], assigns.locale),
        max_export: (top && top["share"]) || 1,
        max_client: (List.first(e["top_clients"]) || %{"share" => 1})["share"] || 1
      )

    ~H"""
    <.section id="commerce">
      <.section_head eyebrow={gettext("Trade")} title={trade_title(@entry, @top_label)}>
        <:intro>{trade_lead(@entry, @doc, @name, @top_label, @locale)}</:intro>
      </.section_head>

      <.stat_grid>
        <:stat
          id="exports"
          label={gettext("Exports of goods · %{year}", year: @doc["year"])}
          value={WorldBankComponents.usd(@entry["exports_usd"], @locale)}
        >
          {trend_text(@entry["exports_by_year"], @locale)}
        </:stat>
        <:stat
          id="imports"
          label={gettext("Imports of goods · %{year}", year: @doc["year"])}
          value={WorldBankComponents.usd(@entry["imports_usd"], @locale)}
        >
          {balance_text(@entry, @locale)}
        </:stat>
        <:stat
          id="first-product"
          label={gettext("First export")}
          value={pct(@entry["first_chapter_share"], @locale)}
        >
          {@top_label} · {tier_label(@entry["concentration"])}
        </:stat>
        <:stat
          id="africa-share"
          label={gettext("Exports to Africa")}
          value={pct(@entry["africa_share_exports"], @locale)}
        >
          {gettext("African median: %{v}", v: pct(@doc["medians"]["africa_share_exports"], @locale))}
        </:stat>
      </.stat_grid>

      <div class="grid grid-2">
        <.card pad class="stack gap-3" id="top-exports">
          <.card_head
            title={gettext("Main exports")}
            subtitle={
              gettext("Share of exports of goods, by HS chapter · %{year}", year: @doc["year"])
            }
          />
          <ul class="share-list">
            <li :for={t <- @entry["top_exports"]}>
              <span>{chapter(@doc, t["chapter"], @locale)}</span>
              <span class="share-track"><span style={"width: #{width(t["share"], @max_export)}%"}></span></span>
              <b class="num">{pct(t["share"], @locale)}</b>
            </li>
          </ul>
        </.card>
        <.card pad class="stack gap-3" id="top-clients">
          <.card_head
            title={gettext("Main clients")}
            subtitle={gettext("Share of exports of goods · %{year}", year: @doc["year"])}
          />
          <ul class="share-list">
            <li :for={t <- @entry["top_clients"]}>
              <span>{partner(@doc, t["code"], @locale)}</span>
              <span class="share-track share-track-alt"><span style={"width: #{width(t["share"], @max_client)}%"}></span></span>
              <b class="num">{pct(t["share"], @locale)}</b>
            </li>
          </ul>
          <p class="small muted">
            {gettext("Main suppliers: %{list}",
              list:
                Enum.map_join(
                  @entry["top_suppliers"],
                  ", ",
                  &"#{partner(@doc, &1["code"], @locale)} #{pct(&1["share"], @locale)}"
                )
            )}
          </p>
        </.card>
      </div>

      <p class="src">
        {gettext(
          "Source: CEPII, BACI (version %{version}, %{nomenclature} nomenclature), Licence Ouverte Etalab 2.0 · goods only, re-exports included · chapters, shares and concentration: Syli Atlas calculation",
          version: @doc["source"]["version"],
          nomenclature: @doc["source"]["nomenclature"]
        )}
      </p>
    </.section>
    """
  end

  def chapter(doc, code, "en"), do: get_in(doc, ["chapters", code, "en"]) || code
  def chapter(doc, code, _), do: get_in(doc, ["chapters", code, "fr"]) || code
  def partner(doc, code, locale), do: get_in(doc, ["partners", code, locale]) || code

  defp trade_title(e, label) do
    case e["concentration"] do
      "high" -> gettext("Exports that depend on one product: %{product}", product: lower(label))
      "medium" -> gettext("Exports led by %{product}", product: lower(label))
      _ -> gettext("Diversified exports")
    end
  end

  defp trade_lead(e, doc, name, label, locale) do
    clients = e["top_clients"] |> Enum.take(2) |> Enum.map(&partner(doc, &1["code"], locale))

    gettext(
      "%{name}: in %{year}, %{label} made up %{share} of goods exports, the five main chapters %{top5}. The first clients were %{clients}; %{africa} of exports went to other African countries.",
      name: name,
      year: doc["year"],
      label: lower(label),
      share: pct(e["first_chapter_share"], locale),
      top5: pct(e["top5_share"], locale),
      clients: Enum.join(clients, gettext(" and ")),
      africa: pct(e["africa_share_exports"], locale)
    )
  end

  defp trend_text(by_year, locale) do
    years = by_year |> Map.keys() |> Enum.sort()

    case years do
      [first | _] = ys when length(ys) > 1 ->
        a = by_year[first]
        b = by_year[List.last(ys)]

        gettext("%{change} since %{year}",
          change: if(b >= a, do: "+", else: "") <> pct(100 * (b / a - 1), locale),
          year: first
        )

      _ ->
        ""
    end
  end

  defp balance_text(e, locale) do
    diff = e["exports_usd"] - e["imports_usd"]

    if diff >= 0,
      do: gettext("trade surplus of %{v}", v: WorldBankComponents.usd(diff, locale)),
      else: gettext("trade deficit of %{v}", v: WorldBankComponents.usd(-diff, locale))
  end

  defp tier_label("high"), do: gettext("highly concentrated")
  defp tier_label("medium"), do: gettext("concentrated")
  defp tier_label("low"), do: gettext("diversified")
  defp tier_label(_), do: ""

  defp width(v, max) when is_number(v) and max > 0, do: Float.round(min(100.0, 100 * v / max), 1)
  defp width(_, _), do: 0

  defp lower(nil), do: ""
  defp lower(text), do: String.downcase(String.first(text)) <> String.slice(text, 1..-1//1)

  defp pct(nil, _), do: "—"
  defp pct(v, locale), do: number(v, 1, locale) <> " %"
end
