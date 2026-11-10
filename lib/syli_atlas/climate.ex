defmodule SyliAtlas.Climate do
  @moduledoc """
  Business climate of African countries, from two World Bank sources:

    * Worldwide Governance Indicators (WGI): regulatory quality, rule of law,
      government effectiveness, control of corruption; scores from 0 to 100.
    * Business Ready (B-READY): three pillars from 0 to 100, for the African
      economies covered so far (29 in the 2025 edition).

  Syli Atlas gives no « business friendly » verdict of its own: each
  indicator is shown with its source and the country's position against
  the African median. The bundled file is `priv/data/business_climate.json`
  (`mix climate.refresh` updates the WGI part from the World Bank API).
  Kept in memory: country pages add no query for it.
  """

  @wgi ~w(regulatory_quality rule_of_law government_effectiveness control_of_corruption)
  @bready ~w(regulatory_framework public_services operational_efficiency)
  @key {__MODULE__, :document}

  def wgi_keys, do: @wgi
  def bready_keys, do: @bready
  def path, do: Application.app_dir(:syli_atlas, "priv/data/business_climate.json")

  @doc "The document: sources, and per country each indicator with its African rank and median."
  def document do
    case :persistent_term.get(@key, nil) do
      nil ->
        doc = path() |> File.read!() |> Jason.decode!() |> build()
        :persistent_term.put(@key, doc)
        doc

      doc ->
        doc
    end
  end

  @doc "A country's entry, or nil when no source covers it."
  def for_country(code) do
    entry = document()["countries"][code]
    if entry && (entry["wgi"] || entry["bready"]), do: entry
  end

  @doc false
  def build(%{"countries" => raw} = file) do
    wgi = stats(raw, "wgi", @wgi)
    bready = stats(raw, "bready", ["overall" | @bready])

    countries =
      Map.new(raw, fn {code, e} ->
        entry = %{
          "wgi" => e["wgi"] && indicators(code, e["wgi"], @wgi, wgi),
          "bready" => e["bready"] && indicators(code, e["bready"], ["overall" | @bready], bready)
        }

        {code, Map.put(entry, "position", position(entry))}
      end)

    %{
      "as_of" => file["as_of"],
      "sources" => file["sources"],
      "covered" => %{
        "wgi" => Enum.count(raw, fn {_, e} -> e["wgi"] end),
        "bready" => Enum.count(raw, fn {_, e} -> e["bready"] end)
      },
      "countries" => countries
    }
  end

  # For each indicator: the median and every country's rank (1 = best).
  defp stats(raw, source, keys) do
    Map.new(keys, fn key ->
      values =
        raw
        |> Enum.flat_map(fn {code, e} ->
          case get_in(e, [source, key]) do
            nil -> []
            v -> [{code, v}]
          end
        end)
        |> Enum.sort_by(fn {_code, v} -> -v end)

      ranks = values |> Enum.with_index(1) |> Map.new(fn {{code, _}, i} -> {code, i} end)

      {key,
       %{
         "median" => median(Enum.map(values, &elem(&1, 1))),
         "ranks" => ranks,
         "of" => length(values)
       }}
    end)
  end

  defp indicators(code, values, keys, stats) do
    Map.new(keys, fn key ->
      s = stats[key]
      score = values[key]

      {key,
       %{
         "score" => score,
         "median" => s["median"],
         "rank" => s["ranks"][code],
         "of" => s["of"],
         "above" => score > s["median"]
       }}
    end)
  end

  # How many indicators are above the African median (B-READY counts once, by its overall score).
  defp position(entry) do
    flags =
      Enum.map(@wgi, &(entry["wgi"] && entry["wgi"][&1]["above"])) ++
        [entry["bready"] && entry["bready"]["overall"]["above"]]

    known = Enum.reject(flags, &is_nil/1)
    above = Enum.count(known, & &1)

    tier =
      cond do
        known == [] -> nil
        above * 4 >= length(known) * 3 -> "above"
        above * 4 <= length(known) -> "below"
        true -> "middle"
      end

    %{"above" => above, "of" => length(known), "tier" => tier}
  end

  defp median([]), do: nil

  defp median(values) do
    sorted = Enum.sort(values)
    n = length(sorted)
    mid = div(n, 2)

    if rem(n, 2) == 1,
      do: Enum.at(sorted, mid),
      else: Float.round((Enum.at(sorted, mid - 1) + Enum.at(sorted, mid)) / 2, 2)
  end
end
