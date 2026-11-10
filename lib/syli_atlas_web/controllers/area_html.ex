defmodule SyliAtlasWeb.AreaHTML do
  use SyliAtlasWeb, :html
  alias SyliAtlas.Geo.Area
  alias SyliAtlasWeb.{Charts, EconomyComponents, RatingComponents}

  embed_templates "area_html/*"

  def kind_label("country"), do: gettext("Country")
  def kind_label("region"), do: gettext("Region")
  def kind_label("continent"), do: gettext("Continent")
  def kind_label(_), do: gettext("Area")

  attr :area, :map, required: true
  attr :region, :map, default: nil
  attr :name, :string, required: true
  attr :locale, :string, required: true

  def area_header(assigns) do
    ~H"""
    <div class="stack gap-3">
      <nav aria-label={gettext("Breadcrumb")}>
        <ol class="crumbs">
          <li><a href={Paths.home(@locale)}>Syli Atlas</a></li>
          <li :if={@region}>
            <a href={Paths.area(@locale, @region)}>{Area.name(@region, @locale)}</a>
          </li>
          <li aria-current="page">{@name}</li>
        </ol>
      </nav>
      <p class="eyebrow">{kind_label(@area.kind)} · {@area.code}</p>
      <h1 class="display area-title">{@name}</h1>
    </div>
    """
  end

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
