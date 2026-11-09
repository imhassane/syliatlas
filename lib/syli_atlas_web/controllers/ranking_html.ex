defmodule SyliAtlasWeb.RankingHTML do
  use SyliAtlasWeb, :html
  embed_templates "ranking_html/*"

  @doc "Current choice, shown on the phone's filters button."
  def filters_summary(assigns) do
    region =
      if assigns.region,
        do: SyliAtlas.Geo.Area.name(assigns.region, assigns.locale),
        else: gettext("All Africa")

    Enum.join(
      [indicator_label(assigns.indicator), region, "#{assigns.from} → #{assigns.to}"],
      " · "
    )
  end
end
