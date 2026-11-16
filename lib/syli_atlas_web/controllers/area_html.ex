defmodule SyliAtlasWeb.AreaHTML do
  use SyliAtlasWeb, :html

  alias SyliAtlasWeb.{
    Charts,
    EconomyComponents,
    NationalComponents,
    ProfileComponents,
    RatingComponents,
    RebasingComponents,
    TradeComponents,
    WorldBankComponents
  }

  embed_templates "area_html/*"

  attr :items, :list, required: true
  attr :name, :string, required: true

  @doc "Questions of the Trade and Society tabs (also given as FAQPage)."
  def tab_questions(assigns) do
    ~H"""
    <.section id="questions-onglet" variant="alt">
      <.section_head
        eyebrow={gettext("Questions")}
        title={gettext("What people ask about %{name}", names(@name, []))}
      />
      <.faq items={@items} />
    </.section>
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
    do: money_value(PublicData.at(profile["series"][k], to), k, locale, to)

  @doc "A country's official figures of an indicator, as marks for the chart (oldest first)."
  def national_points(nil, _indicator), do: []

  def national_points(entry, indicator) do
    (entry["figures"][indicator] || %{})
    |> Map.values()
    |> Enum.sort_by(& &1["year"])
    |> Enum.map(&Map.take(&1, ~w(year value period status)))
  end

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

  @doc "The editorial address (CONTACT_EMAIL), or nil."
  def contact_email, do: Application.get_env(:syli_atlas, :site, [])[:contact_email]
end
