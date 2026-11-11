defmodule SyliAtlasWeb.Api.V1 do
  @moduledoc """
  The public format of API v1, built from the precomputed documents.

  Every JSON answer is `{"data": …, "meta": …}`:

    * `data`: what was asked;
    * `meta`: the sources of the figures (with the attribution to copy),
      the documentation, and the parameters the answer was computed with.

  Names are always `{fr, en}`; series are lists aligned with `years.list`;
  changes are split by unit (`change_percent`, `change_points`). The shape
  is described field by field in `SyliAtlasWeb.Api.Spec`, and the tests
  check every answer against it.
  """
  alias SyliAtlas.{Geo, Sources}
  alias SyliAtlas.Profiles.Queries
  alias SyliAtlas.Sources.Indicators
  alias SyliAtlasWeb.Api.Catalog
  alias SyliAtlasWeb.Paths

  # Areas ---------------------------------------------------------------

  @doc "Every area."
  def areas do
    areas = Enum.map(Geo.list_areas(), &area_ref/1)
    %{data: areas, meta: meta([], %{count: length(areas)})}
  end

  @doc "One area with its series. `{:ok, answer}` or `:not_found`."
  def area(code, from, to) do
    case Queries.area_profile(code, from, to) do
      nil ->
        :not_found

      json ->
        %{"profile" => p, "period" => period} = Jason.decode!(json)
        edition = p["edition"]
        {:ok, %{data: area_data(p, period), meta: meta([source(edition)], %{from: from, to: to})}}
    end
  end

  defp area_data(p, period) do
    p
    |> ref_from_doc()
    |> Map.merge(%{
      members: members(p),
      years: years(p["years"]),
      series: series(p["series"]),
      share_of_africa_gdp:
        p["share_of_africa_gdp"] || List.duplicate(nil, length(Indicators.years())),
      missing: Enum.map(p["missing"] || [], &%{indicator: &1["indicator"], years: &1["years"]}),
      period: changes(period["from"], period["to"], period["changes"] || %{}),
      rank: rank(p["default_period"])
    })
  end

  @doc "Several areas side by side, in the asked order."
  def compare(codes, from, to) do
    items =
      codes
      |> Enum.map(&Queries.area_profile(&1, from, to))
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&Jason.decode!/1)

    data =
      for %{"profile" => p, "period" => period} <- items do
        p
        |> ref_from_doc()
        |> Map.merge(%{
          years: years(p["years"]),
          series: series(p["series"]),
          period: changes(period["from"], period["to"], period["changes"] || %{})
        })
      end

    sources = items |> Enum.map(& &1["profile"]["edition"]) |> Enum.uniq() |> Enum.map(&source/1)
    %{data: data, meta: meta(sources, %{from: from, to: to, codes: codes})}
  end

  @doc "Countries ranked on an indicator, best first; countries without a value last."
  def ranking(indicator, mode, region, from, to) do
    rows =
      Queries.ranking(indicator, from, to, region: region, mode: mode, locale: "fr")
      |> Jason.decode!()

    areas = Map.new(Geo.list_areas(), &{&1.code, &1})

    data =
      rows
      |> Enum.with_index(1)
      |> Enum.map(fn {row, position} ->
        area = areas[row["code"]]

        area
        |> area_ref()
        |> Map.merge(%{position: if(row["value"], do: position), value: row["value"]})
      end)

    unit = if mode == "value", do: Catalog.unit(indicator), else: Catalog.change_unit(indicator)
    edition = Sources.published_edition("imf_weo")

    %{
      data: data,
      meta:
        meta(edition_sources(edition), %{
          indicator: indicator,
          mode: mode,
          unit: unit,
          region: region,
          from: from,
          to: to
        })
    }
  end

  @doc "The dictionary: every indicator, with its unit and source."
  def indicators do
    data =
      for i <- Catalog.indicators() do
        %{
          key: i.key,
          name: i.name,
          description: i.description,
          unit: i.unit,
          kind: i.kind,
          change_unit: i.change_unit,
          source: %{id: "imf_weo", code: i.imf_code}
        }
      end

    edition = Sources.published_edition("imf_weo")
    %{data: data, meta: meta(edition_sources(edition), %{years: years_span()})}
  end

  # Pieces ------------------------------------------------------------

  defp area_ref(%Geo.Area{} = a) do
    %{
      code: a.code,
      kind: a.kind,
      region: a.region_code,
      name: %{fr: a.name_fr, en: a.name_en},
      slug: %{fr: a.slug_fr, en: a.slug_en},
      pages: pages(a.kind, %{"fr" => a.slug_fr, "en" => a.slug_en})
    }
  end

  defp ref_from_doc(p) do
    %{
      code: p["code"],
      kind: p["kind"],
      region: p["region"],
      name: %{fr: p["name"]["fr"], en: p["name"]["en"]},
      slug: %{fr: p["slug"]["fr"], en: p["slug"]["en"]},
      pages: pages(p["kind"], p["slug"])
    }
  end

  # The site's pages of an area. IMF aggregates have none.
  defp pages("imf_aggregate", _slug), do: nil

  defp pages(kind, slug) do
    base = SyliAtlasWeb.Endpoint.url()

    %{
      fr: base <> Paths.area("fr", kind, slug["fr"]),
      en: base <> Paths.area("en", kind, slug["en"])
    }
  end

  # The countries that make up a region or the continent. Empty for a country
  # and for the IMF aggregates (their composition is the IMF's).
  defp members(%{"kind" => kind, "members" => members}) when kind in ["region", "continent"],
    do: members || []

  defp members(_), do: []

  defp years(y) do
    list = Indicators.years()

    %{
      first: y["first"],
      last: y["last"],
      estimate_from: y["estimate_from"],
      projection_from: y["projection_from"],
      list: list,
      status:
        Enum.map(list, fn year ->
          Indicators.status_for(year, %{
            estimate_from: y["estimate_from"],
            projection_from: y["projection_from"]
          })
        end)
    }
  end

  defp series(series) do
    n = length(Indicators.years())
    Map.new(Catalog.indicator_keys(), &{&1, series[&1] || List.duplicate(nil, n)})
  end

  defp changes(from, to, changes) do
    {points, percent} =
      Catalog.indicator_keys()
      |> Enum.split_with(&(Catalog.change_unit(&1) == "points"))

    %{
      from: from,
      to: to,
      change_percent: Map.new(percent, &{&1, changes[&1]}),
      change_points: Map.new(points, &{&1, changes[&1]})
    }
  end

  # The area's place among African countries by real GDP growth over the
  # default period (computed once per edition). None for regions and aggregates.
  defp rank(%{"rank" => %{} = r} = d) do
    %{
      from: d["from"],
      to: d["to"],
      indicator: "real_gdp_index",
      change_percent: d["real_gdp_change_pct"],
      africa: %{position: r["africa"], out_of: r["of_africa"]},
      region: %{position: r["region"], out_of: r["of_region"]}
    }
  end

  defp rank(_), do: nil

  defp years_span, do: %{first: Indicators.first_year(), last: Indicators.last_year()}

  defp edition_sources(nil), do: []

  defp edition_sources(edition),
    do: [source(%{"source" => "imf_weo", "id" => edition.code, "label" => edition.label})]

  @doc "A source, with the attribution to copy."
  def source(%{"id" => id, "label" => label}) do
    month = edition_month(id)

    %{
      id: "imf_weo",
      name: %{fr: "Perspectives de l'économie mondiale", en: "World Economic Outlook"},
      publisher: %{fr: "Fonds monétaire international", en: "International Monetary Fund"},
      edition: id,
      label: label,
      url: "https://www.imf.org/en/Publications/WEO",
      licence: "IMF Copyright and Usage",
      licence_url: "https://www.imf.org/en/About/copyright-and-terms",
      attribution: %{
        fr:
          "Source : Fonds monétaire international, Perspectives de l'économie mondiale (#{month.fr}), https://www.imf.org/en/Publications/WEO, via Syli Atlas",
        en:
          "Source: International Monetary Fund, World Economic Outlook (#{month.en}), https://www.imf.org/en/Publications/WEO, via Syli Atlas"
      }
    }
  end

  @months_fr ~w(janvier février mars avril mai juin juillet août septembre octobre novembre décembre)
  @months_en ~w(January February March April May June July August September October November December)

  defp edition_month(<<year::binary-size(4), "-", month::binary-size(2)>>) do
    i = String.to_integer(month) - 1
    %{fr: Enum.at(@months_fr, i) <> " " <> year, en: Enum.at(@months_en, i) <> " " <> year}
  end

  defp edition_month(id), do: %{fr: id, en: id}

  @doc "The `meta` of an answer: its sources, the documentation, and extra keys."
  def meta(sources, extra \\ %{}) do
    base = SyliAtlasWeb.Endpoint.url()

    Map.merge(
      %{sources: sources, docs: %{fr: base <> Paths.api("fr"), en: base <> Paths.api("en")}},
      extra
    )
  end
end
