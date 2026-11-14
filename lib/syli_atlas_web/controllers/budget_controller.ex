defmodule SyliAtlasWeb.BudgetController do
  @moduledoc """
  The state budgets of the 54 countries: who votes them, revenue and
  expenditure in % of GDP (IMF) for every country, the finance laws
  collected so far and the latest ones voted. Filtered by region, sorted by
  any column.
  """
  use SyliAtlasWeb, :controller

  alias SyliAtlas.{Budgets, Geo}
  alias SyliAtlasWeb.{Paths, Seo}

  plug :put_layout, false

  @sorts ~w(name expenditure revenue balance law)

  def index(conn, params) do
    locale = conn.assigns.locale
    paths = SyliAtlas.Locales.each(fn l -> Paths.budgets(l) end)
    doc = Budgets.overview()
    regions = Geo.list_regions()
    region = Enum.find(regions, &(&1.code == params["region"]))
    sort = if params["sort"] in @sorts, do: params["sort"], else: "expenditure"
    countries = Map.new(Geo.list_countries(), &{&1.code, &1})

    all =
      for r <- doc["countries"], area = countries[r["code"]], area != nil do
        Map.merge(r, %{
          "name" => Geo.Area.name(area, locale),
          "slug" => Geo.Area.slug(area, locale),
          "region" => area.region_code
        })
      end

    rows =
      all
      |> Enum.filter(&(region == nil or &1["region"] == region.code))
      |> Enum.sort_by(&sort_key(&1, sort))

    latest =
      for l <- doc["latest"], area = countries[l["country_code"]], area != nil do
        Map.merge(l, %{"name" => Geo.Area.name(area, locale), "area" => area})
      end

    answer = answer(all, doc, locale)

    title =
      gettext("State budgets of the 54 African countries: revenue, expenditure, finance laws")

    render(conn, :index,
      page_title: title,
      seo:
        Seo.page(locale, paths, answer, %{
          json_ld: [
            Seo.breadcrumbs([
              {"Syli Atlas", Paths.home(locale)},
              {gettext("State budgets"), paths[locale]}
            ]),
            Seo.dataset(
              name: gettext("State budgets of the 54 African countries"),
              description:
                gettext(
                  "Revenue and expenditure of the general government in % of GDP (IMF, Fiscal Monitor) for each African country, the body that votes the budget, and the finance laws collected by Syli Atlas from official texts."
                ),
              path: paths[locale],
              locale: locale,
              area: %{name: gettext("Africa")},
              based_on: {"IMF, " <> (doc["imf"]["label"] || "Fiscal Monitor"), doc["imf"]["url"]},
              modified: doc["built_at"]
            )
          ]
        }),
      alternates: Seo.alternates_for_header(paths),
      rows: rows,
      latest: latest,
      regions: regions,
      region: region,
      sort: sort,
      year: doc["year"],
      doc: doc,
      answer: answer,
      fx: if(latest != [], do: SyliAtlas.Fx.latest()),
      counts:
        Map.new([nil | regions], fn
          nil -> {nil, length(all)}
          r -> {r.code, Enum.count(all, &(&1["region"] == r.code))}
        end)
    )
  end

  # Largest first, unknown values last; names in alphabetical order.
  defp sort_key(row, "name"), do: {0, String.normalize(row["name"], :nfd)}

  defp sort_key(row, "law") do
    case row["latest_law"] do
      nil -> {1, ""}
      l -> {0, invert(l["last_date"] || "")}
    end
  end

  defp sort_key(row, sort) do
    v =
      case sort do
        "expenditure" -> row["expenditure_pct"]
        "revenue" -> row["revenue_pct"]
        "balance" -> row["balance_pct"]
      end

    if is_number(v), do: {0, -v}, else: {1, 0}
  end

  # Latest date first, as a sortable string.
  defp invert(iso), do: iso |> String.to_charlist() |> Enum.map(&(255 - &1))

  @doc false
  def answer(rows, doc, locale) do
    exps = for r <- rows, is_number(r["expenditure_pct"]), do: r["expenditure_pct"]
    official = doc["counts"]["official"]

    base =
      gettext(
        "In %{year}, African governments spend a median %{median} of GDP, according to the IMF (from %{low} to %{high}).",
        year: doc["year"],
        median: pct(median(exps), locale),
        low: pct(Enum.min(exps, fn -> nil end), locale),
        high: pct(Enum.max(exps, fn -> nil end), locale)
      )

    laws =
      if official > 0,
        do:
          ngettext(
            "Syli Atlas has the official finance law of 1 country, checked against the official text.",
            "Syli Atlas has the official finance law of %{count} countries, checked against the official text.",
            official
          ),
        else:
          gettext("Finance laws are added country by country, checked against the official text.")

    base <> " " <> laws
  end

  defp pct(nil, _), do: "—"
  defp pct(v, locale), do: SyliAtlasWeb.Format.number(v, 1, locale) <> " %"

  defp median([]), do: nil

  defp median(values) do
    s = Enum.sort(values)
    n = length(s)

    if rem(n, 2) == 1,
      do: Enum.at(s, div(n, 2)),
      else: (Enum.at(s, div(n, 2) - 1) + Enum.at(s, div(n, 2))) / 2
  end
end
