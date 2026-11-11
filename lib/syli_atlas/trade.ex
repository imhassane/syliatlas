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

  The bundled file is `priv/data/trade.json`, built by
  `scripts/build_trade.py` from the BACI archive. Kept in memory.
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
      "first_chapter_share" => median(for {_, c} <- countries, do: c["first_chapter_share"])
    }

    countries =
      Map.new(countries, fn {code, c} ->
        {code, Map.put(c, "concentration", tier(c["first_chapter_share"]))}
      end)

    file
    |> Map.put("countries", countries)
    |> Map.put("medians", medians)
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
