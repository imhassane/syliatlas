defmodule SyliAtlasWeb.WorldBankComponents do
  @moduledoc """
  Country profile sections built on World Bank data (`SyliAtlas.WorldBank`):
  external debt by creditor, financial inflows, structure of the economy and
  jobs, living conditions. Each figure shows its year (World Bank series end
  at different dates) and its source, including the body that compiles the
  series when the Bank republishes it.
  """
  use Phoenix.Component
  use Gettext, backend: SyliAtlasWeb.Gettext

  import SyliAtlasWeb.UI
  import SyliAtlasWeb.Format, only: [number: 3]

  @creditors ~w(multilateral china other_bilateral bonds private)

  def creditor_keys, do: @creditors

  def creditor_label("multilateral"), do: gettext("Multilateral (IMF, World Bank, AfDB…)")
  def creditor_label("china"), do: gettext("China")
  def creditor_label("other_bilateral"), do: gettext("Other countries")
  def creditor_label("bonds"), do: gettext("Bonds (Eurobonds)")
  def creditor_label("private"), do: gettext("Banks and other private lenders")

  def creditor_color("multilateral"), do: "--c1"
  def creditor_color("china"), do: "--c3"
  def creditor_color("other_bilateral"), do: "--c5"
  def creditor_color("bonds"), do: "--c2"
  def creditor_color("private"), do: "--ink-subtle"

  attr :entry, :map, required: true
  attr :doc, :map, required: true
  attr :name, :string, required: true
  attr :debt_pct, :any, default: nil, doc: "IMF public debt, % of GDP, for the headline"
  attr :debt_year, :integer, default: nil
  attr :distress, :map, default: nil, doc: "IMF risk of debt distress, or nil when not assessed"
  attr :distress_doc, :map, default: %{}
  attr :locale, :string, required: true

  @doc "External debt: total, by creditor, and its service."
  def debt_section(assigns) do
    latest = assigns.entry["latest"]

    assigns =
      assign(assigns,
        c: assigns.entry["creditors"],
        ext: latest["external_debt_usd"],
        service: latest["ppg_service_pct_exports"]
      )

    ~H"""
    <.section id="dette">
      <.section_head eyebrow={gettext("Debt")} title={debt_title(@c, @name)}>
        <:intro>{debt_lead(@c, @name, @locale)}</:intro>
        <:actions>
          <a class="btn btn-secondary" href={SyliAtlasWeb.Paths.debt(@locale)}>{gettext(
            "Debt of the 54 countries"
          )} →</a>
        </:actions>
      </.section_head>

      <.stat_grid>
        <:stat
          :if={@debt_pct}
          id="debt-imf"
          label={gettext("Public debt · %{year}", year: @debt_year)}
          value={pct(@debt_pct, @locale)}
        >
          {gettext("of GDP · IMF")}
        </:stat>
        <:stat
          :if={@ext}
          id="external-debt"
          label={gettext("External debt · %{year}", year: @ext["year"])}
          value={usd(@ext["value"], @locale)}
        >
          {gettext("public and private · World Bank")}
        </:stat>
        <:stat
          :if={@c}
          id="ppg-debt"
          label={gettext("Public external debt · %{year}", year: @c["year"])}
          value={usd(@c["total_usd"], @locale)}
        >
          {gettext("owed or guaranteed by the State")}
        </:stat>
        <:stat
          :if={@service}
          id="debt-service"
          label={gettext("Debt service · %{year}", year: @service["year"])}
          value={pct(@service["value"], @locale)}
        >
          {gettext("of exports of goods, services and income")}
        </:stat>
      </.stat_grid>

      <.card :if={@distress} pad class="stack gap-3" id="debt-distress">
        <.card_head
          title={gettext("Risk of debt distress")}
          subtitle={gettext("IMF and World Bank debt sustainability analysis")}
        />
        <div class="risk-scale" role="img" aria-label={risk_label(@distress["risk"])}>
          <span
            :for={r <- ~w(low moderate high distress)}
            class={["risk-step", "risk-" <> r, @distress["risk"] == r && "risk-current"]}
          >
            {risk_label(r)}
          </span>
        </div>
        <p>
          {gettext("Latest analysis published on %{date}: %{risk}.",
            date: @distress["published"],
            risk: String.downcase(risk_label(@distress["risk"]))
          )}
          <span :if={@distress["arrears"]}>{gettext(
            "The country has unresolved arrears to external creditors."
          )}</span>
          <span :if={@distress["restructuring"]}>{gettext(
            "The debt is being restructured under an IMF programme."
          )}</span>
        </p>
        <p class="src">
          {gettext(
            "Source: IMF, list of debt sustainability analyses of low-income countries, as of %{date}",
            date: @distress_doc["as_of"]
          )} · <a href={@distress_doc["source"]["url"]} rel="noopener">imf.org</a>
        </p>
      </.card>

      <.card :if={@c} pad class="stack gap-4" id="creditors">
        <.card_head
          title={gettext("Public external debt by creditor")}
          subtitle={gettext("Share of the total at the end of each year")}
        />
        <ul class="legend share-legend">
          <li :for={k <- creditor_keys()} style={"--dot: var(#{creditor_color(k)})"}>
            <i aria-hidden="true"></i>{creditor_label(k)}
          </li>
        </ul>
        <div class="creditor-rows">
          <div :for={h <- @entry["creditors_history"] ++ [@c]} class="creditor-row">
            <span class="mono small">{h["year"]}</span>
            <div
              class="stacked-bar"
              role="img"
              aria-label={bar_label(h, @locale)}
            >
              <span
                :for={k <- creditor_keys()}
                :if={h["shares"][k] > 0}
                style={"flex: #{h["shares"][k]}; background: var(#{creditor_color(k)})"}
              ></span>
            </div>
          </div>
        </div>
        <dl class="creditor-shares">
          <div :for={k <- creditor_keys()}>
            <dt>{creditor_label(k)}</dt>
            <dd class="num">{pct(@c["shares"][k], @locale)}</dd>
          </div>
        </dl>
        <p class="src">
          {gettext(
            "Source: World Bank, International Debt Statistics (updated %{date}) · public and publicly guaranteed external debt, end of year · CC BY 4.0 · shares: Syli Atlas calculation",
            date: @doc["sources"]["ids"]["last_updated"]
          )}
        </p>
      </.card>
    </.section>
    """
  end

  attr :entry, :map, required: true
  attr :doc, :map, required: true
  attr :name, :string, required: true
  attr :locale, :string, required: true

  @doc "Foreign direct investment, remittances and aid, side by side."
  def flows_section(assigns) do
    latest = assigns.entry["latest"]

    rows =
      for {id, label, pct_key, usd_key, base} <- [
            {"fdi", gettext("Foreign direct investment, net inflows"), "fdi_pct_gdp", "fdi_usd",
             gettext("of GDP")},
            {"remittances", gettext("Remittances from the diaspora"), "remittances_pct_gdp",
             "remittances_usd", gettext("of GDP")},
            {"oda", gettext("Official development assistance, net"), "oda_pct_gni", "oda_usd",
             gettext("of gross national income")}
          ] do
        %{
          id: id,
          label: label,
          key: pct_key,
          base: base,
          share: latest[pct_key],
          usd: latest[usd_key]
        }
      end

    assigns = assign(assigns, rows: rows)

    ~H"""
    <.section id="flux" variant="alt">
      <.section_head
        eyebrow={gettext("Financial inflows")}
        title={gettext("The money that comes into the country")}
      >
        <:intro>
          {gettext(
            "Investment, money sent home by the diaspora and aid: three inflows often mixed up, shown side by side."
          )}
        </:intro>
      </.section_head>
      <div class="grid grid-3">
        <.card :for={r <- @rows} pad class="stack gap-2" id={"flow-" <> r.id}>
          <p class="eyebrow">{r.label}</p>
          <%= if r.share do %>
            <p class="big num">{pct(r.share["value"], @locale)}</p>
            <p class="small muted">
              {r.base} · {r.share["year"]}
              <span :if={r.usd}>· {usd(r.usd["value"], @locale)}</span>
            </p>
            <p class="small muted">{median_text(@doc, r.key, r.share["value"], @locale)}</p>
          <% else %>
            <p class="big subtle">—</p>
            <p class="small muted">{gettext("No World Bank figure")}</p>
          <% end %>
        </.card>
      </div>
      <p class="src">
        {gettext(
          "Source: World Bank, World Development Indicators (updated %{date}), CC BY 4.0 · investment: IMF balance of payments data · remittances: World Bank and KNOMAD · aid: OECD Development Assistance Committee",
          date: @doc["sources"]["wdi"]["last_updated"]
        )}
      </p>
    </.section>
    """
  end

  attr :entry, :map, required: true
  attr :doc, :map, required: true
  attr :locale, :string, required: true

  @doc "Value added by sector, jobs by sector, and the ILO labour estimates."
  def jobs_section(assigns) do
    l = assigns.entry["latest"]

    assigns =
      assign(assigns,
        output:
          sector_bar(l, [
            {"agriculture_pct_gdp", gettext("Agriculture"), "--c4"},
            {"industry_only", gettext("Industry (excluding manufacturing)"), "--c5"},
            {"manufacturing_pct_gdp", gettext("Manufacturing"), "--c2"},
            {"services_pct_gdp", gettext("Services"), "--c1"}
          ]),
        jobs:
          sector_bar(l, [
            {"jobs_agriculture", gettext("Agriculture"), "--c4"},
            {"jobs_industry", gettext("Industry"), "--c5"},
            {"jobs_services", gettext("Services"), "--c1"}
          ]),
        labour:
          for(
            {k, label} <- [
              {"unemployment_ilo", gettext("Unemployment")},
              {"youth_unemployment", gettext("Unemployment, ages 15–24")},
              {"vulnerable_employment", gettext("Vulnerable employment")},
              {"female_participation", gettext("Women in the labour force")}
            ],
            l[k],
            do: %{key: k, label: label, year: l[k]["year"], value: l[k]["value"]}
          )
      )

    ~H"""
    <.section id="emploi">
      <.section_head
        eyebrow={gettext("Structure of the economy and jobs")}
        title={gettext("What the economy produces, and how people work")}
      />
      <.stat_grid :if={@labour != []}>
        <:stat
          :for={x <- @labour}
          id={x.key}
          label={"#{x.label} · #{x.year}"}
          value={pct(x.value, @locale)}
        >
          {stat_note(x.key)}
        </:stat>
      </.stat_grid>
      <div class="grid grid-2">
        <.card :if={@output} pad class="stack gap-3" id="value-added">
          <.card_head
            title={gettext("Value added by sector, % of GDP")}
            subtitle={"#{@output.year}"}
          />
          <.sector_bar bar={@output} locale={@locale} />
          <p class="src">{gettext("Source: World Bank, World Development Indicators, CC BY 4.0")}</p>
        </.card>
        <.card :if={@jobs} pad class="stack gap-3" id="jobs-by-sector">
          <.card_head title={gettext("Jobs by sector, % of employment")} subtitle={"#{@jobs.year}"} />
          <.sector_bar bar={@jobs} locale={@locale} />
          <p class="src">
            {gettext(
              "Source: ILO, modelled estimates, via World Bank World Development Indicators, CC BY 4.0"
            )}
          </p>
        </.card>
      </div>
      <p class="src">
        {gettext(
          "Unemployment and jobs: ILO modelled estimates, via the World Bank. They differ from national surveys, which count informal work in different ways."
        )}
      </p>
    </.section>
    """
  end

  attr :bar, :map, required: true
  attr :locale, :string, required: true

  def sector_bar(assigns) do
    ~H"""
    <div class="stacked-bar stacked-bar-lg" role="img" aria-label={sector_label(@bar, @locale)}>
      <span :for={p <- @bar.parts} style={"flex: #{p.value}; background: var(#{p.color})"}></span>
    </div>
    <ul class="legend share-legend">
      <li :for={p <- @bar.parts} style={"--dot: var(#{p.color})"}>
        <i aria-hidden="true"></i>{p.label} {pct(p.value, @locale)}
      </li>
    </ul>
    """
  end

  attr :entry, :map, required: true
  attr :doc, :map, required: true
  attr :name, :string, required: true
  attr :locale, :string, required: true

  @doc "Poverty, inequality, electricity, internet and accounts, against the African median."
  def living_section(assigns) do
    assigns =
      assign(assigns,
        rows:
          Enum.filter(
            [
              {"poverty", gettext("Poverty (under $3.00 a day, 2021 PPP)"),
               gettext("Poverty and Inequality Platform")},
              {"gini", gettext("Inequality (Gini index, 0 to 100)"),
               gettext("Poverty and Inequality Platform")},
              {"electricity", gettext("Access to electricity"), "WDI"},
              {"internet", gettext("Internet users"), gettext("WDI, from the ITU")},
              {"accounts", gettext("Adults with an account (bank or mobile money)"),
               "Global Findex"}
            ],
            fn {k, _, _} -> assigns.entry["latest"][k] end
          )
      )

    ~H"""
    <.section :if={@rows != []} id="conditions-de-vie" variant="alt">
      <.section_head
        eyebrow={gettext("Living conditions")}
        title={gettext("What growth changes in daily life")}
      >
        <:intro>
          {gettext(
            "Each indicator is compared with the African median, with the year of the latest survey: some are run only every three to five years."
          )}
        </:intro>
      </.section_head>
      <.card>
        <.data_table id="living-table" caption={gettext("Living conditions")} rows={@rows}>
          <:head :let={{_k, label, _src}} label={gettext("Indicator")}>{label}</:head>
          <:col :let={{k, _, _}} label={@name}>
            <b>{value(@entry["latest"][k], k, @locale)}</b>
          </:col>
          <:col :let={{k, _, _}} label={gettext("African median")}>
            {value(%{"value" => @doc["medians"][k]}, k, @locale)}
          </:col>
          <:col :let={{k, _, _}} label={gettext("Year")}>{@entry["latest"][k]["year"]}</:col>
          <:col :let={{_k, _, src}} label={gettext("Source")} class="l">{src}</:col>
        </.data_table>
        <.card_foot>
          {gettext(
            "Source: World Bank (updated %{date}), CC BY 4.0 · medians of the latest values of each country: Syli Atlas calculation",
            date: @doc["sources"]["wdi"]["last_updated"]
          )}
        </.card_foot>
      </.card>
    </.section>
    """
  end

  def risk_label("low"), do: gettext("Low")
  def risk_label("moderate"), do: gettext("Moderate")
  def risk_label("high"), do: gettext("High")
  def risk_label("distress"), do: gettext("In debt distress")
  def risk_label(_), do: gettext("Not assessed")

  def risk_class(nil), do: "pill-neutral"
  def risk_class(%{"risk" => r}), do: "risk-pill risk-" <> r

  # Helpers --------------------------------------------------------------

  defp sector_bar(latest, parts) do
    latest =
      case {latest["industry_pct_gdp"], latest["manufacturing_pct_gdp"]} do
        {%{"value" => i, "year" => y}, %{"value" => m, "year" => y}} ->
          Map.put(latest, "industry_only", %{"value" => max(i - m, 0), "year" => y})

        _ ->
          latest
      end

    found = for {k, label, color} <- parts, v = latest[k], do: {v, label, color}
    years = found |> Enum.map(fn {v, _, _} -> v["year"] end) |> Enum.uniq()

    if length(found) == length(parts) and length(years) == 1 do
      %{
        year: hd(years),
        parts:
          for({v, label, color} <- found, do: %{value: v["value"], label: label, color: color})
      }
    end
  end

  defp stat_note("unemployment_ilo"), do: gettext("of the labour force · ILO")
  defp stat_note("youth_unemployment"), do: gettext("of young people in the labour force · ILO")

  defp stat_note("vulnerable_employment"),
    do: gettext("own-account and family workers, of all jobs · ILO")

  defp stat_note("female_participation"), do: gettext("of women aged 15 and over · ILO")

  defp debt_title(nil, name), do: gettext("The debt of %{name}", name: name)

  defp debt_title(%{"shares" => s}, _name) do
    {top, _} = Enum.max_by(s, fn {_k, v} -> v end)

    case top do
      "multilateral" -> gettext("A debt owed first to multilateral lenders")
      "china" -> gettext("A debt owed first to China")
      "other_bilateral" -> gettext("A debt owed first to other countries")
      "bonds" -> gettext("A debt owed first to bond holders")
      "private" -> gettext("A debt owed first to banks and private lenders")
    end
  end

  defp debt_lead(nil, name, _locale),
    do: gettext("The World Bank publishes no external debt figures for %{name}.", name: name)

  defp debt_lead(c, name, locale) do
    gettext(
      "At the end of %{year}, %{name} owed %{total} in public external debt (World Bank). %{china} of it was owed to China, %{multilateral} to multilateral institutions and %{bonds} to bond holders.",
      year: c["year"],
      name: name,
      total: usd(c["total_usd"], locale),
      china: pct(c["shares"]["china"], locale),
      multilateral: pct(c["shares"]["multilateral"], locale),
      bonds: pct(c["shares"]["bonds"], locale)
    )
  end

  defp bar_label(h, locale) do
    "#{h["year"]} : " <>
      Enum.map_join(@creditors, ", ", &"#{creditor_label(&1)} #{pct(h["shares"][&1], locale)}")
  end

  defp sector_label(bar, locale),
    do:
      "#{bar.year} : " <> Enum.map_join(bar.parts, ", ", &"#{&1.label} #{pct(&1.value, locale)}")

  defp median_text(doc, key, v, locale) do
    case doc["medians"][key] do
      nil ->
        ""

      m ->
        gettext("African median: %{median} · %{position}",
          median: pct(m, locale),
          position: if(v >= m, do: gettext("above"), else: gettext("below"))
        )
    end
  end

  defp value(nil, _key, _locale), do: "—"
  defp value(%{"value" => nil}, _key, _locale), do: "—"
  defp value(%{"value" => v}, "gini", locale), do: number(v, 1, locale)
  defp value(%{"value" => v}, _key, locale), do: pct(v, locale)

  defp pct(nil, _locale), do: "—"
  defp pct(v, locale), do: number(v, 1, locale) <> " %"

  @doc false
  def usd(nil, _locale), do: "—"

  def usd(v, locale) do
    cond do
      abs(v) >= 1.0e9 ->
        number(v / 1.0e9, 1, locale) <> " " <> SyliAtlasWeb.Format.billions(locale)

      true ->
        number(v / 1.0e6, 0, locale) <> if(locale == "en", do: " m$", else: " M$")
    end
  end
end
