defmodule SyliAtlas.Trade do
  @moduledoc """
  Goods trade of African countries, from CEPII's BACI (Licence Ouverte
  Etalab 2.0): exports and imports, main export chapters, main clients and
  suppliers, and the share of trade with other African countries.

  BACI reconciles what exporters and importers declare to UN Comtrade, so
  countries that report little still have figures; re-exports are included.

  The concentration tier is Syli Atlas's reading of the first chapter's
  share of exports, shown as such: 50 % or more "highly concentrated",
  25 % or more "concentrated", below "diversified".

  Since November 2026 each country also carries its main products (HS
  4-digit headings) with their buyers, the stage of processing of its
  exports and imports (BEC rev. 5, United Nations), its trade with every
  other African country, the "African potential" (products bought outside
  Africa that other African countries already export, a Syli Atlas
  calculation) and its exports since 1995 (BACI HS 1992).

  The bundled file is `priv/data/trade.json`, built by
  `scripts/build_trade.py` from the BACI archives. Kept in memory.
  """

  @key {__MODULE__, :document}

  def path, do: Application.app_dir(:syli_atlas, "priv/data/trade.json")

  def document do
    case :persistent_term.get(@key, nil) do
      nil ->
        doc =
          if File.exists?(path()),
            do: path() |> File.read!() |> Jason.decode!() |> build(),
            else: build(%{"countries" => %{}})

        :persistent_term.put(@key, doc)
        doc

      doc ->
        doc
    end
  end

  def for_country(code), do: document()["countries"][code]

  @doc false
  def build(%{"countries" => countries} = file) do
    medians = %{
      "africa_share_exports" => median(for {_, c} <- countries, do: c["africa_share_exports"]),
      "first_chapter_share" => median(for {_, c} <- countries, do: c["first_chapter_share"]),
      "raw_share_exports" =>
        median(for {_, c} <- countries, do: raw_share(get_in(c, ["stages", "exports"])))
    }

    countries =
      Map.new(countries, fn {code, c} ->
        {code, Map.put(c, "concentration", tier(c["first_chapter_share"]))}
      end)

    file
    |> Map.put("countries", countries)
    |> Map.put("medians", medians)
  end

  @doc """
  Share of raw materials, unprocessed or barely processed: primary goods
  (BEC) plus gold, precious stones and unwrought metals, which the BEC counts
  as processed. Nil without stages.
  """
  def raw_share(%{"primary" => p} = stages) when is_number(p),
    do: Float.round(p + (stages["unwrought"] || 0) * 1.0, 1)

  def raw_share(_), do: nil

  @doc "Label of an HS 4-digit heading: French on French pages, English elsewhere."
  def heading(doc, code, "fr"), do: get_in(doc, ["headings", code, "fr"]) || code
  def heading(doc, code, _locale), do: get_in(doc, ["headings", code, "en"]) || code

  @doc """
  Share of a country's exports and imports that go to, and come from, the
  members of each of its communities: `[{community, export %, import %}]`.
  """
  def community_shares(nil, _communities), do: []

  def community_shares(entry, communities) do
    trade = entry["africa_trade"] || %{}

    for c <- communities do
      {exp, imp} =
        Enum.reduce(c.members, {0, 0}, fn m, {e, i} ->
          case trade[m] do
            [ev, iv] -> {e + ev, i + iv}
            _ -> {e, i}
          end
        end)

      {c, share(exp, entry["exports_usd"]), share(imp, entry["imports_usd"])}
    end
  end

  defp share(_v, total) when not is_number(total) or total == 0, do: nil
  defp share(v, total), do: Float.round(100 * v / total, 1)

  @doc "Exports per year since 1995 (BACI HS 1992), sorted, or [] when absent."
  def history(nil), do: []

  def history(entry) do
    (get_in(entry, ["history", "exports"]) || %{})
    |> Enum.map(fn {y, v} -> {String.to_integer(y), v} end)
    |> Enum.sort()
  end

  @doc "Concentration tier from the first chapter's share of exports."
  def tier(share) when is_number(share) and share >= 50, do: "high"
  def tier(share) when is_number(share) and share >= 25, do: "medium"
  def tier(share) when is_number(share), do: "low"
  def tier(_), do: nil

  defp median(values) do
    case values |> Enum.filter(&is_number/1) |> Enum.sort() do
      [] ->
        nil

      s ->
        n = length(s)
        mid = div(n, 2)
        if rem(n, 2) == 1, do: Enum.at(s, mid), else: (Enum.at(s, mid - 1) + Enum.at(s, mid)) / 2
    end
  end
end
