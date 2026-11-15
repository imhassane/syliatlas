defmodule SyliAtlasWeb.IndicatorYear do
  @moduledoc """
  Pages for one indicator of one country in one year, the way people search
  (« pib mauritanie 2025 », « burundi gdp 2025 »): `/fr/pays/mauritanie/pib-2025`.

  Every year from the IMF series has a page, but only the years around the
  default arrival year are indexed and listed in the sitemap: the others stay
  readable, out of the index, so that the site does not multiply thin pages.
  """
  alias SyliAtlasWeb.Paths

  @indicators [
    {"gdp_usd_bn", %{"fr" => "pib", "es" => "pib", "pt" => "pib", "en" => "gdp"}},
    {"gdp_per_capita_usd",
     %{
       "fr" => "pib-par-habitant",
       "es" => "pib-per-capita",
       "pt" => "pib-per-capita",
       "en" => "gdp-per-capita"
     }},
    {"real_gdp_growth",
     %{"fr" => "croissance", "es" => "crecimiento", "pt" => "crescimento", "en" => "growth"}},
    {"inflation",
     %{"fr" => "inflation", "es" => "inflacion", "pt" => "inflacao", "en" => "inflation"}},
    {"public_debt_pct_gdp",
     %{
       "fr" => "dette-publique",
       "es" => "deuda-publica",
       "pt" => "divida-publica",
       "en" => "public-debt"
     }}
  ]

  def keys, do: Enum.map(@indicators, &elem(&1, 0))

  @doc "The address segment of an indicator in a language (« pib-2025 »)."
  def segment(key, year, locale) do
    {_, slugs} = List.keyfind(@indicators, key, 0)
    (slugs[locale] || slugs["en"]) <> "-" <> Integer.to_string(year)
  end

  @doc "`{key, year}` for an address segment of any language, or nil."
  def parse(segment) when is_binary(segment) do
    with [_, slug, year] <- Regex.run(~r/^([a-z-]+)-(\d{4})$/, segment),
         {key, _} <- Enum.find(@indicators, fn {_, s} -> slug in Map.values(s) end),
         y = String.to_integer(year),
         true <- y in SyliAtlas.Sources.Indicators.years() do
      {key, y}
    else
      _ -> nil
    end
  end

  def parse(_), do: nil

  def path(locale, area, key, year),
    do:
      Paths.area(locale, "country", SyliAtlas.Geo.Area.slug(area, locale)) <>
        "/" <> segment(key, year, locale)

  @doc "The years indexed and listed: the arrival year of the default period, the one before and the one after."
  def indexed_years do
    {_from, to} = SyliAtlas.Profiles.Builder.default_period()
    [to - 1, to, to + 1]
  end
end
