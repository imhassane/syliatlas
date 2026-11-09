defmodule SyliAtlasWeb.AreaHTML do
  use SyliAtlasWeb, :html
  alias SyliAtlasWeb.Charts

  embed_templates "area_html/*"

  def kind_label("country"), do: gettext("Country")
  def kind_label("region"), do: gettext("Region")
  def kind_label("continent"), do: gettext("Continent")
  def kind_label(_), do: gettext("Area")

  @doc "Series embedded in the page so the browser recomputes the period offline."
  def embedded_json(profile) do
    Jason.encode!(%{code: profile["code"], series: profile["series"], years: profile["years"]})
  end

  def citation(name, edition, url) do
    "Syli Atlas, « #{name} », #{url}. " <>
      gettext("Data: IMF, %{label}.", label: edition["label"])
  end
end
