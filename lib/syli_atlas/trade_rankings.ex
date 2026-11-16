defmodule SyliAtlas.TradeRankings do
  @moduledoc """
  The three trade rankings of the 54 countries, from the country entries of
  `SyliAtlas.Trade` (CEPII, BACI):

  - `"dependence"`: share of the first product (HS 4-digit heading) in the
    country's exports of goods;
  - `"raw"`: share of raw or barely processed materials in its exports
    (BEC rev. 5 « primary », plus gold, precious stones and unwrought
    metals: `SyliAtlas.Trade.raw_share/1`);
  - `"intra"`: share of its exports sold to other African countries.

  Every row carries what the page shows next to the value: the first
  product, the total exports, the first African client.
  """

  alias SyliAtlas.{Geo, Trade}
  alias SyliAtlas.Geo.Area

  @ids ~w(dependence raw intra)

  def ids, do: @ids

  @doc """
  Rows of a ranking, largest value first; countries without a value come
  last. Each row: code, name, slug, region, value, exports, product (HS 4
  code of the first product), product_share, client (code of the first
  African client by exports).
  """
  def rows(id, locale) when id in @ids do
    doc = Trade.document()

    Geo.list_countries()
    |> Enum.map(&row(&1, doc["countries"][&1.code], id, locale))
    |> Enum.sort_by(fn r ->
      if is_number(r.value), do: {0, -r.value, r.name}, else: {1, 0, r.name}
    end)
  end

  defp row(%Area{} = area, entry, id, locale) do
    entry = entry || %{}
    first = List.first(entry["top_products"] || [])

    client =
      (entry["africa_partners"] || [])
      |> Enum.filter(&((&1["exports"] || 0) > 0))
      |> Enum.max_by(& &1["exports"], fn -> nil end)

    %{
      code: area.code,
      name: Area.name(area, locale),
      slug: Area.slug(area, locale),
      region: area.region_code,
      value: value(id, entry),
      exports: entry["exports_usd"],
      product: first && first["code"],
      product_share: first && first["share"],
      client: client && client["code"],
      client_value: client && client["exports"]
    }
  end

  defp value("dependence", entry),
    do: get_in(entry, [Access.key("top_products", []), Access.at(0), "share"])

  defp value("raw", entry), do: Trade.raw_share(get_in(entry, ["stages", "exports"]))
  defp value("intra", entry), do: entry["africa_share_exports"]

  @doc "Median of the values (countries with a value)."
  def median(rows) do
    values = rows |> Enum.map(& &1.value) |> Enum.filter(&is_number/1) |> Enum.sort()

    case length(values) do
      0 ->
        nil

      n when rem(n, 2) == 1 ->
        Enum.at(values, div(n, 2))

      n ->
        Float.round((Enum.at(values, div(n, 2) - 1) + Enum.at(values, div(n, 2))) / 2, 1)
    end
  end

  @doc "The rank of each country (1 = largest value), countries without a value excluded."
  def ranks(rows) do
    rows
    |> Enum.filter(&is_number(&1.value))
    |> Enum.with_index(1)
    |> Map.new(fn {r, i} -> {r.code, i} end)
  end
end
