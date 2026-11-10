defmodule SyliAtlas.Profiles.HomeSnapshot do
  @moduledoc """
  Everything the home page shows, computed once per edition and stored as
  the `home:<locale>` snapshot, so a visit costs one query.

  It holds figures and names, never formatted text: wording, translations
  and layout stay in the templates and change without a rebuild. A new
  figure on the home page must be added here; bump `@format` when the
  shape changes, and the snapshot is rebuilt at the next start
  (`SyliAtlas.Release.setup/0`).
  """
  alias SyliAtlas.{Geo, Sources}
  alias SyliAtlas.Geo.Area
  alias SyliAtlas.Profiles.{Builder, Queries}

  @format 1
  @popular ~w(CIV NGA ETH SEN KEN)

  def format, do: @format

  @doc "Builds the document for one locale from the profiles online."
  def build(locale) do
    {from, to} = Builder.default_period()
    area = &decode(Queries.area_profile(&1, from, to))

    ranking =
      Queries.ranking("gdp_usd_bn", from, to, locale: locale)
      |> decode()
      |> Enum.filter(&is_number(&1["value"]))

    edition = Sources.published_edition("imf_weo")
    source = Sources.get_source("imf_weo")

    regions =
      Geo.list_regions()
      |> Enum.map(&area.(&1.code))
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(&(-(&1["period"]["changes"]["gdp_usd_bn"] || -999)))

    %{
      "format" => @format,
      "from" => from,
      "to" => to,
      "africa" => area.("africa"),
      "world" => area.("WLD"),
      "top" => Enum.take(ranking, 3),
      "bottom" => ranking |> Enum.take(-3) |> Enum.reverse(),
      "regions" => regions,
      "popular" => popular(locale),
      "edition" => edition && %{"code" => edition.code, "label" => edition.label},
      "last_checked_at" =>
        source && source.last_checked_at && DateTime.to_iso8601(source.last_checked_at),
      "map" => decode(Queries.map_countries(locale))
    }
  end

  defp popular(locale) do
    for code <- @popular, area = Geo.get_area_by_code(code), area != nil do
      %{"code" => code, "name" => Area.name(area, locale), "slug" => Area.slug(area, locale)}
    end
  end

  defp decode(nil), do: nil
  defp decode(json), do: Jason.decode!(json)
end
