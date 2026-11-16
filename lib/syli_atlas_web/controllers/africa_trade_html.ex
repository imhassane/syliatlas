defmodule SyliAtlasWeb.AfricaTradeHTML do
  use SyliAtlasWeb, :html

  import SyliAtlasWeb.AfricaTradeComponents
  alias SyliAtlas.AfricaTrade
  alias SyliAtlasWeb.{AfricaTradeController, TradeTopics}

  embed_templates "africa_trade_html/*"

  def name(countries, code, locale),
    do: AfricaTradeController.country_name(countries, code, locale)

  def heading(code, locale), do: AfricaTrade.heading(code, locale)

  @doc "Source line of BACI, as each block gives it."
  def source(doc) do
    gettext("Source: CEPII, BACI (version %{version}), Licence Ouverte Etalab 2.0",
      version: doc["source"]["version"]
    )
  end

  def history_source(doc) do
    gettext(
      "Source: CEPII, BACI, HS 1992 nomenclature (version %{version}), Licence Ouverte Etalab 2.0. Series from %{year}: before, BACI reports South Africa together with its customs union neighbours.",
      version: doc["history_source"]["version"],
      year: doc["history_source"]["first_year"]
    )
  end

  @doc "Stage labels, in the order of the bars."
  def stages do
    [
      {"primary", gettext("Raw")},
      {"unwrought", gettext("Gold, stones, unwrought metals")},
      {"intermediate", gettext("Intermediate goods")},
      {"final", gettext("Finished goods")}
    ]
  end

  def kind_label(:export), do: gettext("Mainly exported by Africa")
  def kind_label(:import), do: gettext("Mainly bought by Africa")

  @doc "Rows of a product's main table: exporters or importers."
  def main_rows(p, :export), do: p["exporters"]
  def main_rows(p, :import), do: p["importers"]

  def history_label(id, kind, points, locale) do
    {y0, _, _} = hd(points)
    {y1, e, i} = List.last(points)

    if kind == :export,
      do:
        gettext("%{product}: African exports from %{y0} to %{y1} (%{value} in %{y1})",
          product: TradeTopics.product_name(id),
          y0: y0,
          y1: y1,
          value: usd(e, locale)
        ),
      else:
        gettext("%{product}: African imports from %{y0} to %{y1} (%{value} in %{y1})",
          product: TradeTopics.product_name(id),
          y0: y0,
          y1: y1,
          value: usd(i, locale)
        )
  end

  @doc "Multiple between the first and last year, written « ×37 », or nil."
  def growth([{_, e0, i0} | _] = points, kind) do
    {_, e1, i1} = List.last(points)
    {v0, v1} = if kind == :export, do: {e0, e1}, else: {i0, i1}
    if is_number(v0) and v0 > 0 and is_number(v1), do: v1 / v0
  end

  def growth(_, _), do: nil
end
