defmodule SyliAtlasWeb.AreaHTML do
  use SyliAtlasWeb, :html

  alias SyliAtlasWeb.{
    Charts,
    EconomyComponents,
    ProfileComponents,
    RatingComponents,
    TradeComponents,
    WorldBankComponents
  }

  embed_templates "area_html/*"

  attr :kpis, :list, required: true
  attr :data, :map, required: true
  attr :profile, :map, required: true
  attr :from, :integer, required: true
  attr :to, :integer, required: true
  attr :locale, :string, required: true

  def area_kpis(assigns) do
    ~H"""
    <.stat_grid>
      <:stat
        :for={k <- @kpis}
        id={k}
        label={indicator_label(k)}
        value={kpi_value(k, @data, @profile, @to, @locale)}
        tone={if(k == "real_gdp_index", do: tone(@data["period"]["changes"][k], k))}
      >
        <%= if k == "real_gdp_index" do %>
          {@from} → {@to}
        <% else %>
          {@to} ·
          <span class={tone(@data["period"]["changes"][k], k)}>{change(
            @data["period"]["changes"][k],
            k,
            @locale
          )} {gettext("since %{year}", year: @from)}</span>
        <% end %>
      </:stat>
    </.stat_grid>
    """
  end

  defp kpi_value("real_gdp_index" = k, data, _profile, _to, locale),
    do: change(data["period"]["changes"][k], k, locale)

  defp kpi_value(k, _data, profile, to, locale),
    do: value(PublicData.at(profile["series"][k], to), k, locale)

  @doc "Series embedded in the page so the browser recomputes the period offline."
  def embedded_json(profile) do
    SyliAtlasWeb.MapComponents.json_for_script(%{
      code: profile["code"],
      series: profile["series"],
      years: profile["years"]
    })
  end

  def citation(name, edition, url) do
    "Syli Atlas, « #{name} », #{url}. " <>
      gettext("Data: IMF, %{label}.", label: edition["label"])
  end
end
