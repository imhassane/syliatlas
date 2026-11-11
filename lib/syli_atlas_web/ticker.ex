defmodule SyliAtlasWeb.Ticker do
  @moduledoc """
  What the scrolling band under the header of every public page shows: the
  main index of each exchange at the last close, then the latest rating
  decisions.

  Built from the precomputed documents (`market:overview` and the ratings
  document) and kept in `:persistent_term`, keyed by both data versions: a
  page costs no query for it, and a new close or a validated decision shows
  at once (the page ETags already follow the same versions).

  Only figures that may be shown and that passed the checks:

    * indices: market data public (`SyliAtlas.Market.public?/0`), a value,
      a change, and no quality flag (missing, stale, change to check);
    * ratings: changes of rating or outlook (not affirmations), never a
      decision still marked « to check ».
  """

  alias SyliAtlas.{Market, Ratings}

  @key {__MODULE__, :items}
  @ratings 10
  @rating_actions ~w(upgrade downgrade default outlook_up outlook_down)

  @doc """
  `%{indices: [...], ratings: [...], market_date: iso | nil, market_sources: [...]}`.
  Both lists may be empty: the band then shows only the other one, or nothing.
  """
  def get do
    version = version()

    case :persistent_term.get(@key, nil) do
      {^version, data} ->
        data

      _ ->
        data = build()
        :persistent_term.put(@key, {version, data})
        data
    end
  end

  @doc "Forget the cached band (tests)."
  def reset, do: :persistent_term.erase(@key)

  defp version, do: {Market.data_version(), Ratings.data_version(), Market.public?()}

  @doc false
  def build do
    overview = if Market.public?(), do: Market.overview(), else: nil
    indices = indices(overview)

    shown? = indices != []

    %{
      indices: indices,
      market_date: if(shown?, do: overview["as_of"]),
      market_sources: if(shown?, do: overview["sources"] || [], else: []),
      ratings: ratings(Ratings.document())
    }
  end

  @doc false
  def indices(nil), do: []

  def indices(%{"exchanges" => exchanges}) do
    for x <- exchanges,
        i = x["index"],
        i["value"] != nil,
        i["change_pct"] != nil,
        not flagged?(i["flags"]) do
      %{
        code: x["exchange"]["code"],
        name: x["exchange"]["short_name"],
        value: i["value"],
        change_pct: i["change_pct"]
      }
    end
  end

  defp flagged?(nil), do: false
  defp flagged?(flags), do: Enum.any?(~w(missing stale suspect), &(flags[&1] == true))

  @doc false
  def ratings(nil), do: []

  def ratings(%{"countries" => countries}) do
    countries
    |> Map.values()
    |> Enum.flat_map(fn c ->
      for a <- c["agencies"] || [],
          a["action_type"] in @rating_actions,
          a["needs_check"] != true,
          is_binary(a["action_date"]) and a["action_date"] != "" do
        %{
          country: c["code"],
          name: c["name"],
          slug: c["slug"],
          agency: a["agency"],
          rating: a["rating"],
          action: a["action_type"],
          date: a["action_date"]
        }
      end
    end)
    |> Enum.sort_by(&{&1.date, &1.country}, :desc)
    |> Enum.take(@ratings)
  end
end
