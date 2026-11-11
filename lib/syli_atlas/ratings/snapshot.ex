defmodule SyliAtlas.Ratings.Snapshot do
  @moduledoc """
  The `ratings` document the pages read (the ratings page, the country
  profiles, the home page and its map), rebuilt after every change of the
  ratings table: one row per page.

  It holds figures and names, never wording: verdicts and texts are in
  `SyliAtlasWeb.RatingComponents`. Bump `@format` when the shape changes.
  """
  import Ecto.Query
  alias SyliAtlas.{Geo, Repo}
  alias SyliAtlas.Ratings.{Rating, Scale}

  @format 1
  @agencies ~w(sp moodys fitch)
  @recent 8

  def format, do: @format

  def build do
    current = current_ratings()
    countries = Geo.list_countries()

    entries =
      for area <- countries, into: %{} do
        {area.code, entry(area, Map.get(current, area.code, []))}
      end

    ranked =
      entries
      |> Map.values()
      |> Enum.filter(& &1["average"])
      |> Enum.sort_by(&{-&1["average"], &1["name"]["fr"]})

    ranks = ranked |> Enum.with_index(1) |> Map.new(fn {e, i} -> {e["code"], i} end)
    entries = Map.new(entries, fn {code, e} -> {code, Map.put(e, "rank", ranks[code])} end)

    %{
      "format" => @format,
      "as_of" => as_of(current),
      "rated" => length(ranked),
      "countries" => entries,
      "ranking" => Enum.map(ranked, & &1["code"]),
      "unrated" => countries |> Enum.reject(&Map.has_key?(ranks, &1.code)) |> Enum.map(& &1.code),
      "counts" => Map.new(Scale.bands(), fn b -> {b, Enum.count(ranked, &(&1["band"] == b))} end),
      "recent" => recent(entries)
    }
  end

  # The latest decision of each agency, by country.
  defp current_ratings do
    Repo.all(from r in Rating, where: r.agency in ^@agencies, order_by: [asc: r.action_date])
    |> Enum.group_by(&{&1.country_code, &1.agency})
    |> Enum.map(fn {_key, decisions} -> List.last(decisions) end)
    |> Enum.group_by(& &1.country_code)
  end

  defp entry(area, ratings) do
    agencies =
      for agency <- @agencies, r = Enum.find(ratings, &(&1.agency == agency)), r != nil do
        %{
          "agency" => agency,
          "rating" => r.rating,
          "score" => Scale.score(r.rating),
          "outlook" => r.outlook,
          "action_date" => r.action_date,
          "action_type" => r.action_type,
          "needs_check" => r.needs_check,
          "source_url" => r.source_url
        }
      end

    base = %{
      "code" => area.code,
      "name" => %{"fr" => area.name_fr, "en" => area.name_en},
      "slug" => %{"fr" => area.slug_fr, "en" => area.slug_en},
      "region" => area.region_code,
      "agencies" => agencies
    }

    case Enum.map(agencies, & &1["score"]) do
      [] ->
        Map.merge(base, %{"average" => nil, "label" => nil, "band" => nil, "trend" => nil})

      scores ->
        average = Float.round(Enum.sum(scores) / length(scores), 2)

        Map.merge(base, %{
          "average" => average,
          "label" => Scale.label(average),
          "band" => Scale.band(average),
          "notches" => Scale.notches_to_investment(average),
          "trend" => trend(agencies)
        })
    end
  end

  defp trend(agencies) do
    up = Enum.count(agencies, &(&1["outlook"] == "positive"))
    down = Enum.count(agencies, &(&1["outlook"] == "negative"))

    cond do
      up > down -> "up"
      down > up -> "down"
      true -> "stable"
    end
  end

  defp as_of(current) do
    current
    |> Map.values()
    |> List.flatten()
    |> Enum.map(&DateTime.to_date(&1.updated_at))
    |> Enum.max(Date, fn -> nil end)
    |> then(&(&1 && Date.to_iso8601(&1)))
  end

  # The latest changes of rating (not affirmations), newest first.
  defp recent(entries) do
    entries
    |> Map.values()
    |> Enum.flat_map(fn e ->
      for a <- e["agencies"],
          a["action_type"] in ~w(upgrade downgrade default),
          do: Map.merge(a, %{"code" => e["code"]})
    end)
    |> Enum.sort_by(& &1["action_date"], :desc)
    |> Enum.take(@recent)
  end
end
