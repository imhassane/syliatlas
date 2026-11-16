defmodule SyliAtlas.AfricaTrade do
  @moduledoc """
  Africa's goods trade taken as a whole, and product by product, from
  CEPII's BACI (Licence Ouverte Etalab 2.0): the page « Commerce de
  l'Afrique » and the product pages (cocoa, copper, wheat…).

  The bundled file is `priv/data/africa_trade.json`, built by
  `scripts/build_africa_trade.py` from the BACI archives (HS 2022 for the
  latest year, HS 1992 for the series since 2000). Kept in memory.

  Shares in the world and between countries are Syli Atlas calculations
  from BACI values; the pages say so.
  """

  @key {__MODULE__, :document}

  # Page order of the products: exports of the soil, of the subsoil, then
  # what Africa buys.
  @products ~w(cocoa coffee tea cashew cotton rubber vanilla flowers crude-oil gas gold diamonds
               platinum copper cobalt iron-ore manganese phosphates uranium wheat rice sugar
               palm-oil cars)

  @doc "Product ids, in page order."
  def products, do: @products

  def path, do: Application.app_dir(:syli_atlas, "priv/data/africa_trade.json")

  def document do
    case :persistent_term.get(@key, nil) do
      nil ->
        doc =
          if File.exists?(path()),
            do: path() |> File.read!() |> Jason.decode!(),
            else: %{"products" => %{}, "africa" => nil}

        :persistent_term.put(@key, doc)
        doc

      doc ->
        doc
    end
  end

  @doc "Africa as a whole, or nil when the file is missing."
  def africa, do: document()["africa"]

  @doc "The product page of an HS 4-digit heading, when one product is that heading alone (1801 → cocoa)."
  def product_of_heading(code) do
    Enum.find(@products, fn id ->
      case get_in(document(), ["products", id, "codes"]) do
        [^code] -> true
        _ -> false
      end
    end)
  end

  @doc "A product's figures by id, or nil."
  def product(id), do: document()["products"][id]

  @doc "The product's exports since 2000, sorted: [{year, exports, imports}]."
  def history(%{"history" => h}) when is_map(h) do
    h
    |> Enum.map(fn {y, v} -> {String.to_integer(y), v["exports"], v["imports"]} end)
    |> Enum.sort()
  end

  def history(_), do: []

  @doc """
  Whether Africa mainly sells or mainly buys the product: `:export` when
  its exports exceed its imports, `:import` otherwise. The page puts first
  who sells it, or who buys it and where it comes from.
  """
  def kind(%{"exports" => e, "imports" => i}) when is_number(e) and is_number(i),
    do: if(e >= i, do: :export, else: :import)

  def kind(_), do: :export

  @doc "Name of a country outside Africa (French on French pages, English elsewhere)."
  def partner_name(code, locale) do
    case document()["partners"][code] do
      nil -> code
      names -> if locale == "fr", do: names["fr"], else: names["en"]
    end
  end

  @doc "Label of an HS 4-digit heading in the Africa lists."
  def heading(code, "fr"), do: get_in(document(), ["headings", code, "fr"]) || code
  def heading(code, _locale), do: get_in(document(), ["headings", code, "en"]) || code

  @doc false
  def reload, do: :persistent_term.erase(@key)
end
