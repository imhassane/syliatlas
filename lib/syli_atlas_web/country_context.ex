defmodule SyliAtlasWeb.CountryContext do
  @moduledoc """
  A few figures on a country for pages that are about something else (a
  security, a glossary term, a rating): its sovereign ratings and the IMF's
  growth, inflation and public debt for the year of the default period.
  Read from the stored documents, no query of its own beyond them.
  """
  alias SyliAtlasWeb.PublicData

  @doc "`%{code, name, slug, year, growth, inflation, debt, rating}` or nil."
  def get(nil, _locale), do: nil

  def get(code, locale) do
    {from, to} = SyliAtlas.Profiles.Builder.default_period()

    with %{"profile" => profile} <- PublicData.area(code, from, to) do
      series = profile["series"] || %{}
      rating = SyliAtlas.Ratings.for_country(SyliAtlas.Ratings.document(), code)

      %{
        code: code,
        name: SyliAtlas.Locales.pick(profile["name"], locale),
        slug: SyliAtlas.Locales.pick(profile["slug"], locale),
        year: to,
        status: status(profile, to),
        growth: PublicData.at(series["real_gdp_growth"], to),
        inflation: PublicData.at(series["inflation"], to),
        debt: PublicData.at(series["public_debt_pct_gdp"], to),
        rating: rating
      }
    else
      _ -> nil
    end
  end

  defp status(%{"years" => %{"estimate_from" => est, "projection_from" => proj}}, year)
       when is_integer(est) and is_integer(proj) do
    cond do
      year >= proj -> "projection"
      year >= est -> "estimate"
      true -> "actual"
    end
  end

  defp status(_profile, _year), do: "actual"
end
