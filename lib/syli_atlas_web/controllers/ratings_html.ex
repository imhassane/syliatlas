defmodule SyliAtlasWeb.RatingsHTML do
  use SyliAtlasWeb, :html

  import SyliAtlasWeb.RatingComponents
  alias SyliAtlas.Ratings.Scale

  embed_templates "ratings_html/*"

  def tab_label(nil), do: gettext("All")
  def tab_label("unrated"), do: gettext("Not rated")
  def tab_label(band), do: verdict(band)

  def tab_href(locale, verdict, q) do
    query =
      [{"verdict", verdict}, {"q", if(q != "", do: q)}]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    Paths.ratings(locale) <> if(query == [], do: "", else: "?" <> URI.encode_query(query))
  end

  def agency(entry, code), do: Enum.find(entry["agencies"], &(&1["agency"] == code))

  @doc "Bar width of an average on the common scale, in percent."
  def width(nil), do: 0
  def width(average), do: Float.round(average / Scale.max() * 100, 1)

  def threshold, do: Float.round(Scale.investment_grade() / Scale.max() * 100, 1)
end
