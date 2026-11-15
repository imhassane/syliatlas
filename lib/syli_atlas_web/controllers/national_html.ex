defmodule SyliAtlasWeb.NationalHTML do
  use SyliAtlasWeb, :html

  alias SyliAtlasWeb.Format
  alias SyliAtlasWeb.NationalComponents
  alias SyliAtlasWeb.RebasingComponents

  embed_templates "national_html/*"

  @doc "The figure being checked or counted for a row, from the country's entry."
  def row_figure(doc, row, year) do
    SyliAtlas.National.figure(
      SyliAtlas.National.for_country(doc, row["code"]),
      "gdp_usd_bn",
      year
    )
  end
end
