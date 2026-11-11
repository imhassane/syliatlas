defmodule SyliAtlasWeb.EconomyComponents do
  @moduledoc """
  Sections of a country profile beyond the headline economy: the section
  menu, public finances and external accounts, and the currency. Every
  figure carries its source under it.
  """
  use Phoenix.Component
  use Gettext, backend: SyliAtlasWeb.Gettext

  import SyliAtlasWeb.UI
  import SyliAtlasWeb.PageComponents, only: [indicator_label: 1, chart_legend: 1]
  import SyliAtlasWeb.Format, only: [value: 3, change: 3, tone: 2, number: 3, names: 1, names: 2]
  alias SyliAtlasWeb.{Charts, PublicData}

  attr :items, :list, required: true, doc: "{anchor, label} tuples"

  @doc "Menu of the profile's sections, kept at the top while scrolling."
  def section_nav(assigns) do
    ~H"""
    <nav class="section-nav" aria-label={gettext("Sections of this page")} id="section-nav">
      <div class="wrap section-nav-inner">
        <a :for={{anchor, label} <- @items} href={"#" <> anchor}>{label}</a>
      </div>
    </nav>
    """
  end

  attr :profile, :map, required: true
  attr :data, :map, required: true
  attr :name, :string, required: true
  attr :comparison, :map, default: nil, doc: "%{name, series} of the region or of Africa"
  attr :convergence, :map, default: nil
  attr :from, :integer, required: true
  attr :to, :integer, required: true
  attr :locale, :string, required: true

  @doc "Fiscal balance, public debt, current account and, in the CFA unions, the convergence criteria."
  def finances_section(assigns) do
    s = assigns.profile["series"]
    to = assigns.to

    assigns =
      assign(assigns,
        balance: PublicData.at(s["fiscal_balance_pct_gdp"], to),
        debt: PublicData.at(s["public_debt_pct_gdp"], to),
        current: PublicData.at(s["current_account_pct_gdp"], to),
        keys: ~w(fiscal_balance_pct_gdp public_debt_pct_gdp current_account_pct_gdp)
      )

    ~H"""
    <.section id="finances" variant="alt">
      <.section_head
        eyebrow={gettext("Public finances and external accounts")}
        title={finances_title(@balance, @locale)}
      >
        <:intro>{finances_lead(@name, @balance, @debt, @current, @to, @locale)}</:intro>
      </.section_head>

      <.stat_grid class="stats-3">
        <:stat
          :for={k <- @keys}
          id={k}
          label={"#{indicator_label(k)} · #{@to}"}
          value={value(PublicData.at(@profile["series"][k], @to), k, @locale)}
        >
          {gettext("of GDP")} ·
          <span class={tone(@data["period"]["changes"][k], k)}>{change(
            @data["period"]["changes"][k],
            k,
            @locale
          )} {gettext("since %{year}", year: @from)}</span>
        </:stat>
      </.stat_grid>

      <div class="grid grid-2">
        <.card pad>
          <.card_head
            title={gettext("Fiscal balance, % of GDP")}
            subtitle={gettext("Negative: a deficit · dashed: estimates and projections")}
          />
          <% series =
            [
              %{
                id: @profile["code"] <> "-balance",
                name: @name,
                color: "--c1",
                values: @profile["series"]["fiscal_balance_pct_gdp"],
                strong: true
              }
            ] ++
              if(@comparison,
                do: [
                  %{
                    id: "comparison-balance",
                    name: @comparison.name,
                    color: "--c2",
                    values: @comparison.series["fiscal_balance_pct_gdp"]
                  }
                ],
                else: []
              ) %>
          <Charts.line_chart
            id="balance-chart"
            indicator="fiscal_balance_pct_gdp"
            from={@from}
            to={@to}
            locale={@locale}
            estimate_from={@profile["years"]["estimate_from"]}
            label={finances_lead(@name, @balance, @debt, @current, @to, @locale)}
            series={series}
          />
          <.chart_legend series={series} />
          <p class="src">
            {gettext(
              "Source: IMF, %{label} · general government net lending or borrowing · group values weighted by GDP in dollars (Syli Atlas)",
              label: @profile["edition"]["label"]
            )}
          </p>
        </.card>

        <.convergence_card :if={@convergence} convergence={@convergence} locale={@locale} />

        <.card :if={!@convergence} pad>
          <.card_head
            title={gettext("Current account, % of GDP")}
            subtitle={gettext("Trade, income and transfers with the rest of the world")}
          />
          <Charts.line_chart
            id="current-chart"
            indicator="current_account_pct_gdp"
            from={@from}
            to={@to}
            locale={@locale}
            estimate_from={@profile["years"]["estimate_from"]}
            label={gettext("Current account balance of %{name}, % of GDP", names(@name))}
            series={[
              %{
                id: @profile["code"] <> "-current",
                name: @name,
                color: "--c1",
                values: @profile["series"]["current_account_pct_gdp"],
                strong: true
              }
            ]}
          />
          <p class="src">{gettext("Source: IMF, %{label}", label: @profile["edition"]["label"])}</p>
        </.card>
      </div>
    </.section>
    """
  end

  attr :convergence, :map, required: true
  attr :locale, :string, required: true

  def convergence_card(assigns) do
    ~H"""
    <.card pad class="stack gap-3" id="convergence">
      <.card_head
        title={zone_criteria_title(@convergence.zone)}
        subtitle={gettext("First-rank criteria in %{year}", year: @convergence.year)}
      />
      <ul class="criteria">
        <li :for={c <- @convergence.criteria}>
          <span class="criteria-text">
            <b>{criterion_label(c)}</b>
            <span class="small muted num">{criterion_value(c, @locale)}</span>
          </span>
          <span class={["pill", status_class(c.status)]}>{status_label(c.status)}</span>
        </li>
      </ul>
      <p class="src">
        <%= if @convergence.zone == "uemoa" do %>
          {gettext(
            "Syli Atlas calculation from IMF figures · thresholds: UEMOA Additional Act No. 01/2015/CCEG/UEMOA · fiscal balance: general government net lending or borrowing (IMF), close to the overall balance including grants"
          )}
        <% else %>
          {gettext(
            "Syli Atlas calculation from IMF figures · thresholds: CEMAC multilateral surveillance framework (2016) · the reference fiscal balance is not published by the IMF"
          )}
        <% end %>
      </p>
    </.card>
    """
  end

  attr :currency, :map, required: true

  attr :fx, :map,
    default: nil,
    doc: "%{rate, as_of} for one US dollar, when a market source allows it"

  attr :profile, :map, required: true
  attr :name, :string, required: true
  attr :to, :integer, required: true
  attr :locale, :string, required: true

  @doc "The currency: its peg when it has one, the monetary union, inflation and the dollar rate."
  def money_section(assigns) do
    ~H"""
    <.section id="monnaie">
      <.section_head eyebrow={pgettext("section", "Currency")} title={cap(@currency.name)}>
        <:intro>{money_lead(@currency, @name)}</:intro>
      </.section_head>

      <.stat_grid class={if(@fx, do: nil, else: "stats-3")}>
        <:stat id="currency" label={gettext("Currency")} value={@currency.code}>
          {@currency.name}
        </:stat>
        <:stat
          id="peg"
          label={gettext("Exchange regime")}
          value={if(@currency.peg, do: gettext("Fixed"), else: "—")}
        >
          <%= if @currency.peg do %>
            {peg_text(@currency, @locale)}
          <% else %>
            {gettext("no fixed peg")}
          <% end %>
        </:stat>
        <:stat
          id="inflation-money"
          label={"#{indicator_label("inflation")} · #{@to}"}
          value={value(PublicData.at(@profile["series"]["inflation"], @to), "inflation", @locale)}
        >
          {gettext("average annual change in consumer prices")}
        </:stat>
        <:stat
          :if={@fx}
          id="usd-rate"
          label={gettext("One US dollar")}
          value={"#{number(@fx.rate, if(@fx.rate >= 100, do: 0, else: 2), @locale)} #{@currency.code}"}
        >
          {gettext("rate of %{date}", date: String.slice(@fx.as_of || "", 0, 10))}
        </:stat>
      </.stat_grid>

      <p class="src">
        {gettext(
          "Currency codes: ISO 4217 · fixed parities: central banks (BCEAO, BEAC, Central Bank of the Comoros, Bank of Cape Verde…) · inflation: IMF, %{label}",
          label: @profile["edition"]["label"]
        )}
        <span :if={@fx}>
          · {gettext("dollar rate:")} Data by
          <a href="https://mansaapi.com" rel="noopener">MansaAPI</a>
        </span>
      </p>
    </.section>
    """
  end

  # Text helpers ---------------------------------------------------------

  defp finances_title(nil, _locale), do: gettext("Public finances")

  defp finances_title(balance, locale) when balance < 0,
    do: gettext("A fiscal deficit of %{value} of GDP", value: pct(-balance, locale))

  defp finances_title(balance, locale),
    do: gettext("A fiscal surplus of %{value} of GDP", value: pct(balance, locale))

  @doc false
  def finances_lead(name, balance, debt, current, year, locale) do
    parts =
      [
        balance &&
          if(balance < 0,
            do:
              gettext(
                "in %{year}, the general government spent %{value} of GDP more than it collected",
                year: year,
                value: pct(-balance, locale)
              ),
            else:
              gettext(
                "in %{year}, the general government collected %{value} of GDP more than it spent",
                year: year,
                value: pct(balance, locale)
              )
          ),
        debt && gettext("public debt stood at %{value} of GDP", value: pct(debt, locale)),
        current &&
          if(current < 0,
            do:
              gettext("the current account showed a deficit of %{value}",
                value: pct(-current, locale)
              ),
            else:
              gettext("the current account showed a surplus of %{value}",
                value: pct(current, locale)
              )
          )
      ]
      |> Enum.reject(&(&1 in [nil, false]))

    case parts do
      [] ->
        gettext("The IMF publishes no public finance figures for %{name}.", names(name))

      parts ->
        gettext("%{name}: %{facts} (IMF).", name: name, facts: Enum.join(parts, ", "))
    end
  end

  defp money_lead(%{zone: "uemoa"} = c, name),
    do:
      gettext(
        "%{name} shares the %{currency} and its central bank, the BCEAO, with the seven other UEMOA countries: the policy rate and foreign exchange reserves are common. The franc is pegged to the euro.",
        names(name, currency: c.name)
      )

  defp money_lead(%{zone: "cemac"} = c, name),
    do:
      gettext(
        "%{name} shares the %{currency} and its central bank, the BEAC, with the five other CEMAC countries: the policy rate and foreign exchange reserves are common. The franc is pegged to the euro.",
        names(name, currency: c.name)
      )

  defp money_lead(%{zone: "cma", code: "ZAR"}, _name),
    do:
      gettext(
        "The rand anchors the Common Monetary Area: the currencies of Lesotho, Namibia and Eswatini are at par with it."
      )

  defp money_lead(%{zone: "cma"} = c, name),
    do:
      gettext(
        "%{name} belongs to the Common Monetary Area: the %{currency} is at par with the South African rand, which also circulates in the country.",
        names(name, currency: c.name)
      )

  defp money_lead(%{peg: %{anchor: anchor}} = c, _name),
    do:
      gettext("The %{currency} is pegged to the %{anchor}.",
        currency: c.name,
        anchor: anchor_name(anchor)
      )

  defp money_lead(c, _name),
    do:
      gettext(
        "The %{currency} has no fixed peg: its value against the dollar and the euro moves with the market and the central bank's policy.",
        currency: c.name
      )

  defp peg_text(%{code: code, peg: %{anchor: anchor, rate: rate}}, locale) do
    decimals = if rate == Float.round(rate, 0), do: 0, else: min(5, decimals_of(rate))
    "1 #{anchor} = #{number(rate, decimals, locale)} #{code}"
  end

  defp decimals_of(rate) do
    rate |> Float.to_string() |> String.split(".") |> List.last() |> String.length()
  end

  defp anchor_name("EUR"), do: gettext("euro")
  defp anchor_name("USD"), do: gettext("US dollar")
  defp anchor_name("ZAR"), do: gettext("South African rand")

  defp zone_criteria_title("uemoa"), do: gettext("UEMOA convergence criteria")
  defp zone_criteria_title("cemac"), do: gettext("CEMAC convergence criteria")

  defp criterion_label(%{key: "fiscal_balance"}), do: gettext("Fiscal balance ≥ −3 % of GDP")

  defp criterion_label(%{key: "reference_balance"}),
    do: gettext("Reference fiscal balance ≥ −1.5 % of GDP")

  defp criterion_label(%{key: "inflation"}), do: gettext("Inflation ≤ 3 %")
  defp criterion_label(%{key: "debt"}), do: gettext("Public debt ≤ 70 % of GDP")

  defp criterion_value(%{status: :not_computed}, _locale), do: gettext("not published by the IMF")
  defp criterion_value(%{value: nil}, _locale), do: gettext("no IMF figure")
  defp criterion_value(%{indicator: ind, value: v}, locale), do: value(v, ind, locale)

  defp status_class(:met), do: "pill-ok"
  defp status_class(:missed), do: "pill-warn"
  defp status_class(_), do: "pill-neutral"

  defp status_label(:met), do: gettext("Met")
  defp status_label(:missed), do: gettext("Not met")
  defp status_label(:no_data), do: gettext("No data")
  defp status_label(:not_computed), do: gettext("Not computed")

  defp pct(v, locale), do: number(v, 1, locale) <> " %"
  defp cap(text), do: String.upcase(String.first(text)) <> String.slice(text, 1..-1//1)
end
