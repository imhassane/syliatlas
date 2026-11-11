defmodule SyliAtlas.Profiles.RegionsSnapshot do
  @moduledoc """
  Everything the regions page shows for one period: the five regions,
  their profiles with Africa and the world, who carries each region, and
  the map.

  For the default period it is computed once per edition and stored as the
  `regions:<locale>` snapshot, so a visit costs one query. Any other period
  is computed live by the same `build/3`, so both give the same page.

  It holds figures and names, never formatted text. Bump `@format` when
  the shape changes: the snapshot is rebuilt at the next start
  (`SyliAtlas.Release.setup/0`).
  """
  alias SyliAtlas.Geo
  alias SyliAtlas.Profiles.Queries

  @format 1
  @region_fields ~w(code kind name_fr name_en slug_fr slug_en)a

  def format, do: @format

  @doc "Builds the document for one locale and period from the profiles online."
  def build(locale, from, to) do
    regions = Geo.list_regions()

    areas =
      (Enum.map(regions, & &1.code) ++ ["africa", "WLD"])
      |> Enum.map(&decode(Queries.area_profile(&1, from, to)))
      |> Enum.reject(&is_nil/1)

    %{
      "format" => @format,
      "from" => from,
      "to" => to,
      "regions" => Enum.map(regions, &region_fields/1),
      "areas" => areas,
      "carry" => Enum.map(regions, &carry(&1, from, to, locale)),
      "map" => decode(Queries.map_countries(locale))
    }
  end

  # Who carries a region: the largest economies' share of its GDP in `to`,
  # and its fastest and slowest GDP growth in dollars over the period.
  defp carry(region, from, to, locale) do
    weights =
      Queries.ranking("gdp_usd_bn", from, to, mode: "value", region: region.code, locale: locale)
      |> decode_list()

    growth =
      Queries.ranking("gdp_usd_bn", from, to, region: region.code, locale: locale)
      |> decode_list()
      |> Enum.filter(&is_number(&1["value"]))

    total = weights |> Enum.map(&(&1["value"] || 0)) |> Enum.sum()

    %{
      "region" => region.code,
      "count" => length(weights),
      "heavy" =>
        weights
        |> Enum.take(3)
        |> Enum.map(
          &Map.put(&1, "share", if(total > 0, do: (&1["value"] || 0) / total * 100, else: 0))
        ),
      "fastest" => List.first(growth),
      "slowest" => List.last(growth)
    }
  end

  defp region_fields(region),
    do: Map.new(@region_fields, &{Atom.to_string(&1), Map.fetch!(region, &1)})

  defp decode(nil), do: nil
  defp decode(json), do: Jason.decode!(json)

  defp decode_list(nil), do: []
  defp decode_list(json), do: Jason.decode!(json)
end
