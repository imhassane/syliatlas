defmodule SyliAtlasWeb.SocietyComponents do
  @moduledoc """
  Population, education and health on a country's Society tab, from World
  Development Indicators series that the World Bank republishes under CC BY
  4.0: United Nations population estimates (World Population Prospects,
  World Urbanization Prospects), UNESCO Institute for Statistics, UN IGME,
  WHO and the WHO/UNICEF Joint Monitoring Programme. Each row names the body
  that compiles it.
  """
  use Phoenix.Component
  use Gettext, backend: SyliAtlasWeb.Gettext

  import SyliAtlasWeb.UI
  import SyliAtlasWeb.Format, only: [number: 3, names: 2]

  @bands ~w(0004 0509 1014 1519 2024 2529 3034 3539 4044 4549 5054 5559 6064 6569 7074 7579 80UP)

  attr :entry, :map, required: true
  attr :doc, :map, required: true
  attr :name, :string, required: true
  attr :locale, :string, required: true

  @doc "Population: size, growth, age, towns, and the age pyramid."
  def demography_section(assigns) do
    l = assigns.entry["latest"]

    assigns =
      assign(assigns,
        l: l,
        pyramid: pyramid(l),
        has: Enum.any?(~w(under15_pct urban_pct fertility life_expectancy), &l[&1])
      )

    ~H"""
    <.section :if={@has} id="population">
      <.section_head eyebrow={gettext("Population")} title={demography_title(@l)}>
        <:intro>{demography_lead(@l, @name, @locale)}</:intro>
      </.section_head>
      <.stat_grid>
        <:stat
          :if={@l["under15_pct"]}
          id="under-15"
          label={gettext("Under 15 · %{year}", year: @l["under15_pct"]["year"])}
          value={pct(@l["under15_pct"]["value"], @locale)}
        >
          {median_text(@doc, "under15_pct", @locale)}
        </:stat>
        <:stat
          :if={@l["urban_pct"]}
          id="urban"
          label={gettext("Living in towns · %{year}", year: @l["urban_pct"]["year"])}
          value={pct(@l["urban_pct"]["value"], @locale)}
        >
          {median_text(@doc, "urban_pct", @locale)}
        </:stat>
        <:stat
          :if={@l["fertility"]}
          id="fertility"
          label={gettext("Children per woman · %{year}", year: @l["fertility"]["year"])}
          value={number(@l["fertility"]["value"], 1, @locale)}
        >
          {median_text(@doc, "fertility", @locale, 1)}
        </:stat>
        <:stat
          :if={@l["life_expectancy"]}
          id="life-expectancy"
          label={gettext("Life expectancy · %{year}", year: @l["life_expectancy"]["year"])}
          value={gettext("%{v} years", v: number(@l["life_expectancy"]["value"], 0, @locale))}
        >
          {median_text(@doc, "life_expectancy", @locale, 0)}
        </:stat>
      </.stat_grid>

      <.card :if={@pyramid} pad class="stack gap-3" id="age-pyramid">
        <.card_head
          title={gettext("Age pyramid")}
          subtitle={
            gettext("Share of men and of women in each 5-year age group · %{year}",
              year: @pyramid.year
            )
          }
        />
        <svg
          class="chart"
          viewBox="0 0 640 300"
          role="img"
          aria-label={pyramid_label(@pyramid, @locale)}
        >
          <g :for={b <- @pyramid.rows}>
            <rect x={282 - b.m_w} y={b.y} width={b.m_w} height="13" rx="2" style="fill: var(--c2)">
            </rect>
            <rect x="358" y={b.y} width={b.f_w} height="13" rx="2" style="fill: var(--c1)"></rect>
            <text :if={b.label} x="320" y={b.y + 11} text-anchor="middle">{b.label}</text>
          </g>
          <text x="40" y="14" class="label" style="fill: var(--c2)">{gettext("Men")}</text>
          <text x="600" y="14" text-anchor="end" class="label" style="fill: var(--c1)">
            {gettext("Women")}
          </text>
        </svg>
        <details class="chart-data" id="age-pyramid-data">
          <summary>{gettext("Chart data as a table")}</summary>
          <div class="table-box" role="region" aria-labelledby="age-pyramid-caption" tabindex="0">
            <table class="table">
              <caption id="age-pyramid-caption">{gettext("Age pyramid")}</caption>
              <thead>
                <tr>
                  <th scope="col" class="l">{gettext("Age")}</th>
                  <th scope="col">{gettext("Men")}</th>
                  <th scope="col">{gettext("Women")}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={b <- Enum.reverse(@pyramid.rows)}>
                  <th scope="row" class="l">{b.age}</th>
                  <td>{pct(b.m, @locale)}</td>
                  <td>{pct(b.f, @locale)}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </details>
        <p class="src">
          {gettext(
            "Source: United Nations, World Population Prospects, via World Bank World Development Indicators, CC BY 4.0"
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

  @doc "Education and health, against the African median."
  def education_health_section(assigns) do
    l = assigns.entry["latest"]

    rows =
      Enum.filter(
        [
          {"primary_completion", gettext("Children who complete primary school"),
           gettext("UNESCO Institute for Statistics")},
          {"lower_secondary_completion", gettext("Who complete lower secondary school"),
           gettext("UNESCO Institute for Statistics")},
          {"youth_literacy", gettext("Literacy, 15 to 24 year-olds"),
           gettext("UNESCO Institute for Statistics")},
          {"pupils_per_teacher", gettext("Pupils per teacher, primary school"),
           gettext("UNESCO Institute for Statistics")},
          {"under5_mortality", gettext("Deaths before age 5, per 1,000 births"),
           gettext("UN IGME (UNICEF, WHO, World Bank, UN)")},
          {"maternal_mortality", gettext("Maternal deaths per 100,000 births"), gettext("WHO")},
          {"physicians_per_1000", gettext("Doctors per 1,000 people"), gettext("WHO")},
          {"water_basic", gettext("Access to at least basic drinking water"),
           gettext("WHO/UNICEF JMP")}
        ],
        fn {k, _, _} -> l[k] end
      )

    assigns = assign(assigns, rows: rows, l: l)

    ~H"""
    <.section :if={@rows != []} id="education-sante" variant="alt">
      <.section_head
        eyebrow={gettext("Education and health")}
        title={gettext("School and health care %{in_name}", names(@name, []))}
      >
        <:intro>
          {gettext(
            "Each indicator is compared with the African median, with the year of its latest value: surveys and censuses are not run every year."
          )}
        </:intro>
      </.section_head>
      <.card>
        <.data_table
          id="education-health-table"
          caption={gettext("Education and health")}
          rows={@rows}
        >
          <:head :let={{_k, label, _src}} label={gettext("Indicator")}>{label}</:head>
          <:col :let={{k, _, _}} label={@name}><b>{value(@l[k]["value"], k, @locale)}</b></:col>
          <:col :let={{k, _, _}} label={gettext("African median")}>
            {value(@doc["medians"][k], k, @locale)}
          </:col>
          <:col :let={{k, _, _}} label={gettext("Year")}>{@l[k]["year"]}</:col>
          <:col :let={{_k, _, src}} label={gettext("Source")} class="l">{src}</:col>
        </.data_table>
        <.card_foot>
          {gettext(
            "Source: World Bank, World Development Indicators (updated %{date}), CC BY 4.0, which republishes the series of the bodies named in each row · medians of the latest values of each country: Syli Atlas calculation",
            date: @doc["sources"]["wdi"]["last_updated"]
          )}
        </.card_foot>
      </.card>
    </.section>
    """
  end

  @doc "Questions and answers of the Society tab, shown on the page and as FAQPage."
  def faq_items(_name, nil, _doc, _locale), do: []

  def faq_items(name, entry, _doc, locale) do
    l = entry["latest"]

    [
      l["under15_pct"] &&
        {gettext("How young is the population of %{name}?", names(name, [])),
         gettext("%{v} of the inhabitants are under 15 (%{year}).",
           v: pct(l["under15_pct"]["value"], locale),
           year: l["under15_pct"]["year"]
         )},
      l["life_expectancy"] &&
        {gettext("What is life expectancy in %{name}?", names(name, [])),
         gettext("%{v} years at birth in %{year} (United Nations).",
           v: number(l["life_expectancy"]["value"], 1, locale),
           year: l["life_expectancy"]["year"]
         )},
      l["primary_completion"] &&
        {gettext("How many children finish primary school in %{name}?", names(name, [])),
         gettext("%{v} of children complete primary school (%{year}, UNESCO).",
           v: pct(l["primary_completion"]["value"], locale),
           year: l["primary_completion"]["year"]
         )}
    ]
    |> Enum.filter(& &1)
  end

  # Helpers ----------------------------------------------------------------

  defp demography_title(l) do
    case l["under15_pct"] do
      %{"value" => v} when v >= 40 -> gettext("A very young population")
      %{"value" => v} when v >= 30 -> gettext("A young population")
      _ -> gettext("Who lives there")
    end
  end

  defp demography_lead(l, name, locale) do
    parts =
      [
        l["under15_pct"] &&
          gettext(
            "%{v} of the inhabitants %{of_name} are under 15",
            names(name, v: pct(l["under15_pct"]["value"], locale))
          ),
        l["urban_pct"] &&
          gettext("%{v} live in towns", v: pct(l["urban_pct"]["value"], locale)),
        l["fertility"] &&
          gettext("women have %{v} children on average",
            v: number(l["fertility"]["value"], 1, locale)
          )
      ]
      |> Enum.filter(& &1)

    case parts do
      [] ->
        ""

      _ ->
        Enum.join(parts, ", ") <> ". " <> gettext("Source: United Nations, via the World Bank.")
    end
  end

  defp pyramid(l) do
    rows =
      for {band, i} <- Enum.with_index(@bands),
          m = l["pyramid_ma_" <> String.downcase(band)],
          f = l["pyramid_fe_" <> String.downcase(band)] do
        {band, i, m, f}
      end

    years = rows |> Enum.flat_map(fn {_, _, m, f} -> [m["year"], f["year"]] end) |> Enum.uniq()

    if length(rows) == length(@bands) and length(years) == 1 do
      max = rows |> Enum.flat_map(fn {_, _, m, f} -> [m["value"], f["value"]] end) |> Enum.max()
      scale = 240 / max(max, 1)

      %{
        year: hd(years),
        rows:
          for {band, i, m, f} <- rows do
            %{
              y: 20 + (length(@bands) - 1 - i) * 16,
              m: m["value"],
              f: f["value"],
              m_w: Float.round(m["value"] * scale, 1),
              f_w: Float.round(f["value"] * scale, 1),
              age: age(band),
              label: if(rem(i, 4) == 0, do: age(band))
            }
          end
      }
    end
  end

  defp age("80UP"), do: "80+"

  defp age(<<a::binary-size(2), b::binary-size(2)>>),
    do: "#{String.to_integer(a)}–#{String.to_integer(b)}"

  defp pyramid_label(p, locale) do
    gettext("Age pyramid") <>
      " #{p.year} : " <>
      Enum.map_join(Enum.reverse(p.rows), ", ", fn b ->
        "#{b.age} #{pct(b.m, locale)} / #{pct(b.f, locale)}"
      end)
  end

  defp median_text(doc, key, locale, decimals \\ :pct) do
    case doc["medians"][key] do
      nil ->
        ""

      m ->
        gettext("African median: %{v}",
          v: if(decimals == :pct, do: pct(m, locale), else: number(m, decimals, locale))
        )
    end
  end

  defp value(nil, _key, _locale), do: "—"

  defp value(v, k, locale) when k in ~w(under5_mortality maternal_mortality pupils_per_teacher),
    do: number(v, 0, locale)

  defp value(v, "physicians_per_1000", locale), do: number(v, 2, locale)
  defp value(v, _k, locale), do: pct(v, locale)

  defp pct(nil, _), do: "—"
  defp pct(v, locale), do: number(v, 1, locale) <> " %"
end
