defmodule SyliAtlasWeb.PageComponents do
  @moduledoc "Building blocks shared by the public pages."
  use Phoenix.Component
  use Gettext, backend: SyliAtlasWeb.Gettext

  alias SyliAtlas.Sources.Indicators

  @doc "Human label of an indicator."
  def indicator_label(key) do
    case key do
      "real_gdp_index" -> gettext("Real GDP (volume)")
      "real_gdp_growth" -> gettext("Real GDP growth")
      "gdp_usd_bn" -> gettext("GDP, current dollars")
      "gdp_per_capita_usd" -> gettext("GDP per capita")
      "gdp_per_capita_ppp" -> gettext("GDP per capita, PPP")
      "inflation" -> gettext("Inflation")
      "public_debt_pct_gdp" -> gettext("Public debt")
      "population_m" -> gettext("Population")
    end
  end

  @doc "One-line explanation of an indicator."
  def indicator_help(key) do
    case key do
      "real_gdp_index" ->
        gettext("Volume of output, excluding inflation and exchange rates. 2015 = 100.")

      "real_gdp_growth" ->
        gettext("Annual change in output volume.")

      "gdp_usd_bn" ->
        gettext("Size of the economy at market exchange rates.")

      "gdp_per_capita_usd" ->
        gettext("Average income per person at market exchange rates.")

      "gdp_per_capita_ppp" ->
        gettext("Average income per person, adjusted for local prices.")

      "inflation" ->
        gettext("Annual change in consumer prices, average of the year.")

      "public_debt_pct_gdp" ->
        gettext("Gross debt of the general government, as a share of GDP.")

      "population_m" ->
        gettext("Number of inhabitants, IMF estimate.")
    end
  end

  def year_status(year, years) do
    case Indicators.status_for(year, %{
           estimate_from: years["estimate_from"],
           projection_from: years["projection_from"]
         }) do
      "projection" -> gettext("projection")
      "estimate" -> gettext("estimate")
      _ -> nil
    end
  end

  attr :action, :string, required: true
  attr :from, :integer, required: true
  attr :to, :integer, required: true
  attr :hidden, :list, default: [], doc: "extra {name, value} hidden inputs"

  @doc "Reference and arrival year pickers. Works without JavaScript (GET form)."
  def period_form(assigns) do
    ~H"""
    <form class="period" action={@action} method="get" data-period>
      <input :for={{name, value} <- @hidden} type="hidden" name={name} value={value} />
      <label>
        <span class="eyebrow">{gettext("Since")}</span>
        <select name="from" class="select">
          <option :for={y <- 2015..2029} value={y} selected={y == @from}>{y}</option>
        </select>
      </label>
      <span aria-hidden="true" class="muted">→</span>
      <label>
        <span class="eyebrow">{gettext("Until")}</span>
        <select name="to" class="select">
          <option :for={y <- 2016..2030} value={y} selected={y == @to}>{y}</option>
        </select>
      </label>
      <button type="submit" class="btn btn-secondary btn-sm" data-period-submit>{gettext("Update")}</button>
    </form>
    """
  end

  attr :edition, :map, required: true
  attr :locale, :string, required: true

  def source_line(assigns) do
    ~H"""
    <p class="src">
      {gettext("Source: IMF, %{label}", label: @edition["label"])} · {gettext("copied on %{date}",
        date: String.slice(@edition["fetched_at"] || "", 0, 10)
      )}
    </p>
    """
  end

  @doc "Assigns the period from query params, falling back to the default period."
  def period(params) do
    case SyliAtlasWeb.Api.Params.period(params) do
      {:ok, from, to} -> {from, to}
      {:error, _} -> SyliAtlas.Profiles.Builder.default_period()
    end
  end
end
