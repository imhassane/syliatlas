defmodule SyliAtlasWeb.DebtController do
  @moduledoc """
  The debt of the 54 countries: public debt as a share of GDP (IMF), and
  external debt, its creditors and its service (World Bank). Filtered by
  region, sorted by any column.
  """
  use SyliAtlasWeb, :controller

  alias SyliAtlas.{Geo, WorldBank}
  alias SyliAtlasWeb.{Paths, PublicData, Seo}

  plug :put_layout, false

  @sorts ~w(debt external china bonds service)
  @year 2025

  def index(conn, params) do
    locale = conn.assigns.locale
    paths = %{"fr" => Paths.debt("fr"), "en" => Paths.debt("en")}
    regions = Geo.list_regions()
    region = Enum.find(regions, &(&1.code == params["region"]))
    sort = if params["sort"] in @sorts, do: params["sort"], else: "debt"
    wb = WorldBank.document()

    all =
      PublicData.ranking("public_debt_pct_gdp", @year - 1, @year, mode: "value", locale: locale)
      |> Enum.map(&row(&1, wb))

    rows =
      all
      |> Enum.filter(&(region == nil or &1.region == region.code))
      |> Enum.sort_by(&sort_key(&1, sort))

    answer = answer(all, locale)

    render(conn, :index,
      page_title: gettext("Debt of the 54 African countries: level, creditors, cost"),
      seo:
        Seo.page(locale, paths, answer, %{
          json_ld: [
            Seo.breadcrumbs([
              {"Syli Atlas", Paths.home(locale)},
              {gettext("Debt"), paths[locale]}
            ])
          ]
        }),
      alternates: Seo.alternates_for_header(paths),
      rows: rows,
      regions: regions,
      region: region,
      sort: sort,
      year: @year,
      answer: answer,
      wb: wb,
      counts:
        Map.new([nil | regions], fn
          nil -> {nil, length(all)}
          r -> {r.code, Enum.count(all, &(&1.region == r.code))}
        end)
    )
  end

  defp row(r, wb) do
    entry = WorldBank.for_country(r["code"])
    c = entry && entry["creditors"]
    latest = (entry && entry["latest"]) || %{}

    %{
      code: r["code"],
      name: r["name"],
      slug: r["slug"],
      region: r["region"],
      debt: r["value"],
      external: latest["external_debt_usd"],
      china: c && c["shares"]["china"],
      bonds: c && c["shares"]["bonds"],
      creditors_year: c && c["year"],
      service: latest["ppg_service_pct_exports"],
      wb_as_of: wb["as_of"]
    }
  end

  # Largest first, unknown values last.
  defp sort_key(row, sort) do
    v =
      case sort do
        "debt" -> row.debt
        "external" -> row.external && row.external["value"]
        "china" -> row.china
        "bonds" -> row.bonds
        "service" -> row.service && row.service["value"]
      end

    if is_number(v), do: {0, -v}, else: {1, 0}
  end

  @doc false
  def answer(rows, locale) do
    debts = for r <- rows, is_number(r.debt), do: r.debt
    above = Enum.count(debts, &(&1 > 70))
    chinas = for r <- rows, is_number(r.china), do: r.china

    gettext(
      "In %{year}, the median public debt of African countries is %{median} of GDP (IMF); %{above} of %{of} countries are above 70 %. China holds a median %{china} of their public external debt (World Bank).",
      year: @year,
      median: pct(median(debts), locale),
      above: above,
      of: length(debts),
      china: pct(median(chinas), locale)
    )
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
