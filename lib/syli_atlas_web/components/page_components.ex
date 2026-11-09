defmodule SyliAtlasWeb.PageComponents do
  @moduledoc "Building blocks shared by the public pages."
  use Phoenix.Component
  use Gettext, backend: SyliAtlasWeb.Gettext

  import SyliAtlasWeb.UI
  alias SyliAtlas.Sources.Indicators
  alias SyliAtlasWeb.Format

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
      <.field label={gettext("Since")}>
        <.select name="from" options={Enum.map(2015..2029, &{&1, &1})} selected={@from} />
      </.field>
      <span aria-hidden="true" class="period-arrow">→</span>
      <.field label={gettext("Until")}>
        <.select name="to" options={Enum.map(2016..2030, &{&1, &1})} selected={@to} />
      </.field>
      <button type="submit" class="btn btn-secondary" data-period-submit>{gettext("Update")}</button>
    </form>
    """
  end

  attr :locale, :string, required: true
  attr :value, :string, default: ""
  attr :id, :string, default: "q"
  attr :autofocus, :boolean, default: false

  def search_form(assigns) do
    ~H"""
    <form class="search" role="search" action={SyliAtlasWeb.Paths.search(@locale)} method="get">
      <label for={@id} class="vh">{gettext("Search a country")}</label>
      <svg
        width="18"
        height="18"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="1.8"
        stroke-linecap="round"
        aria-hidden="true"
      ><circle cx="11" cy="11" r="7"></circle><path d="M20 20l-3.5-3.5"></path></svg>
      <input
        id={@id}
        name="q"
        type="search"
        value={@value}
        placeholder={gettext("Search a country or a region…")}
        autocomplete="off"
        autofocus={@autofocus}
      />
      <button type="submit" class="btn btn-primary">{gettext("Search")}</button>
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

  attr :series, :list, required: true, doc: "maps with :name and :color"

  @doc "Legend under a chart; the in-chart end labels are hidden on small screens."
  def chart_legend(assigns) do
    ~H"""
    <ul class="legend">
      <li :for={s <- @series} style={"--dot: var(#{s.color})"}><i aria-hidden="true"></i>{s.name}</li>
    </ul>
    """
  end

  def install_card(assigns) do
    ~H"""
    <div class="install-card" data-install>
      <div class="install-text">
        <SyliAtlasWeb.Layouts.logo size={48} />
        <div class="stack gap-1">
          <h3 class="h2">{gettext("Syli Atlas on your phone")}</h3>
          <p>
            {gettext(
              "Install the app from your browser, no app store needed. Profiles stay readable offline."
            )}
          </p>
        </div>
      </div>
      <button type="button" class="btn btn-on-deep" data-install-button>{gettext("Install the app")}</button>
    </div>
    """
  end

  @doc """
  Turns ranking rows (`code`, `name`, `slug`, `value`) into `UI.rank_list/1`
  items. `mode` is "change" or "value"; `kind` builds the link.
  """
  def rank_items(rows, indicator, locale, from, to, opts \\ []) do
    mode = Keyword.get(opts, :mode, "change")

    max =
      Keyword.get_lazy(opts, :bar_max, fn ->
        rows |> Enum.map(&abs(&1["value"] || 0)) |> Enum.max(fn -> 0 end)
      end)

    Enum.map(rows, fn r ->
      v = r["value"]

      %{
        key: r["code"],
        name: r["name"],
        href:
          SyliAtlasWeb.Paths.with_period(
            SyliAtlasWeb.Paths.area(locale, r["kind"] || "country", r["slug"]),
            from,
            to
          ),
        value:
          if(mode == "value",
            do: Format.value(v, indicator, locale),
            else: Format.change(v, indicator, locale)
          ),
        tone: Format.tone(v, indicator),
        bar: if(is_number(v) and max > 0, do: round(abs(v) / max * 100), else: 0),
        neg: is_number(v) and v < 0
      }
    end)
  end

  @doc "Assigns the period from query params, falling back to the default period."
  def period(params) do
    case SyliAtlasWeb.Api.Params.period(params) do
      {:ok, from, to} -> {from, to}
      {:error, _} -> SyliAtlas.Profiles.Builder.default_period()
    end
  end

  attr :page, SyliAtlasWeb.Pagination, required: true
  attr :href, :any, required: true

  @doc "Pagination of a ranked list, with the site's labels."
  def list_pager(assigns) do
    ~H"""
    <.pagination
      page={@page}
      href={@href}
      label={gettext("Pages")}
      prev_label={gettext("Previous")}
      next_label={gettext("Next")}
      summary={
        gettext("%{first}–%{last} of %{total}",
          first: @page.offset + 1,
          last: @page.offset + length(@page.entries),
          total: @page.total
        )
      }
    />
    """
  end
end
