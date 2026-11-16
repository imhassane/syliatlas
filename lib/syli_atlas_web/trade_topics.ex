defmodule SyliAtlasWeb.TradeTopics do
  @moduledoc """
  Names and addresses of the trade pages that compare countries or look at
  Africa as a whole (SyliAtlasWeb.TradeRankingController,
  SyliAtlasWeb.AfricaTradeController):

  - three trade rankings, under the ranking address:
    `/fr/classement/dependance-premier-produit`, `/en/ranking/export-dependence`;
  - Africa's trade, `/fr/afrique/commerce`, `/en/africa/trade`;
  - one page per product, `/fr/afrique/produits/cacao`, `/en/africa/products/cocoa`.

  Slugs exist in French, English, Spanish and Portuguese; the other
  languages use the English ones, like the rest of the site.
  """
  use Gettext, backend: SyliAtlasWeb.Gettext

  alias SyliAtlas.Locales
  alias SyliAtlasWeb.Paths

  # Rankings -----------------------------------------------------------------

  @rankings [
    {"dependence", "dependance-premier-produit", "export-dependence",
     "dependencia-de-exportaciones", "dependencia-de-exportacoes"},
    {"raw", "matieres-premieres", "raw-materials", "materias-primas", "materias-primas"},
    {"intra", "commerce-intra-africain", "intra-african-trade", "comercio-intraafricano",
     "comercio-intra-africano"}
  ]

  @doc "The trade rankings, in menu order."
  def rankings, do: Enum.map(@rankings, &elem(&1, 0))

  @doc "The slug of a trade ranking in a language."
  def ranking_slug(id, locale), do: slug(@rankings, id, locale)

  @doc "The address of a trade ranking."
  def ranking_path(locale, id), do: Paths.ranking(locale) <> "/" <> ranking_slug(id, locale)

  @doc "Its file: `/fr/classement/dependance-premier-produit.csv`."
  def ranking_csv_path(locale, id), do: ranking_path(locale, id) <> ".csv"

  @doc "Short name of a trade ranking (tabs, links)."
  def ranking_label("dependence"), do: gettext("Dependence on one product")
  def ranking_label("raw"), do: gettext("Raw materials")
  def ranking_label("intra"), do: gettext("Trade with Africa")

  # Products -----------------------------------------------------------------

  @products [
    {"cocoa", "cacao", "cocoa", "cacao", "cacau"},
    {"coffee", "cafe", "coffee", "cafe", "cafe"},
    {"tea", "the", "tea", "te", "cha"},
    {"cashew", "noix-de-cajou", "cashew-nuts", "anacardos", "castanha-de-caju"},
    {"cotton", "coton", "cotton", "algodon", "algodao"},
    {"rubber", "caoutchouc", "natural-rubber", "caucho", "borracha"},
    {"vanilla", "vanille", "vanilla", "vainilla", "baunilha"},
    {"flowers", "fleurs-coupees", "cut-flowers", "flores-cortadas", "flores-de-corte"},
    {"crude-oil", "petrole-brut", "crude-oil", "petroleo-crudo", "petroleo-bruto"},
    {"gas", "gaz", "gas", "gas", "gas"},
    {"gold", "or", "gold", "oro", "ouro"},
    {"diamonds", "diamants", "diamonds", "diamantes", "diamantes"},
    {"platinum", "platine", "platinum", "platino", "platina"},
    {"copper", "cuivre", "copper", "cobre", "cobre"},
    {"cobalt", "cobalt", "cobalt", "cobalto", "cobalto"},
    {"iron-ore", "minerai-de-fer", "iron-ore", "mineral-de-hierro", "minerio-de-ferro"},
    {"manganese", "manganese", "manganese", "manganeso", "manganes"},
    {"phosphates", "phosphates", "phosphates", "fosfatos", "fosfatos"},
    {"uranium", "uranium", "uranium", "uranio", "uranio"},
    {"wheat", "ble", "wheat", "trigo", "trigo"},
    {"rice", "riz", "rice", "arroz", "arroz"},
    {"sugar", "sucre", "sugar", "azucar", "acucar"},
    {"palm-oil", "huile-de-palme", "palm-oil", "aceite-de-palma", "oleo-de-palma"},
    {"cars", "voitures", "cars", "automoviles", "automoveis"}
  ]

  @doc "The product of a slug, in any language, or nil."
  def product_id(slug), do: id_of_slug(@products, slug)

  def product_slug(id, locale), do: slug(@products, id, locale)

  @africa_segment %{"fr" => "afrique", "en" => "africa", "es" => "africa", "pt" => "africa"}
  @products_segment %{
    "fr" => "produits",
    "en" => "products",
    "es" => "productos",
    "pt" => "produtos"
  }

  def africa_segment(locale), do: @africa_segment[Locales.base(locale)]
  def products_segment(locale), do: @products_segment[Locales.base(locale)]

  @doc "Africa's trade: /fr/afrique/commerce, /en/africa/trade."
  def africa_path(locale),
    do: "/#{locale}/#{africa_segment(locale)}/" <> Paths.tab_segment(locale, :trade)

  @doc "Every product: /fr/afrique/produits."
  def products_path(locale),
    do: "/#{locale}/#{africa_segment(locale)}/#{products_segment(locale)}"

  def product_path(locale, id), do: products_path(locale) <> "/" <> product_slug(id, locale)
  def product_csv_path(locale, id), do: product_path(locale, id) <> ".csv"
  def africa_csv_path(locale), do: africa_path(locale) <> ".csv"

  @doc "Name of a product, as a heading or a list item."
  def product_name("cocoa"), do: gettext("Cocoa")
  def product_name("coffee"), do: gettext("Coffee")
  def product_name("tea"), do: gettext("Tea")
  def product_name("cashew"), do: gettext("Cashew nuts")
  def product_name("cotton"), do: gettext("Cotton")
  def product_name("rubber"), do: gettext("Natural rubber")
  def product_name("vanilla"), do: gettext("Vanilla")
  def product_name("flowers"), do: gettext("Cut flowers")
  def product_name("crude-oil"), do: gettext("Crude oil")
  def product_name("gas"), do: gettext("Natural gas and LPG")
  def product_name("gold"), do: gettext("Gold")
  def product_name("diamonds"), do: gettext("Diamonds")
  def product_name("platinum"), do: gettext("Platinum and platinum metals")
  def product_name("copper"), do: gettext("Copper")
  def product_name("cobalt"), do: gettext("Cobalt")
  def product_name("iron-ore"), do: gettext("Iron ore")
  def product_name("manganese"), do: gettext("Manganese ore")
  def product_name("phosphates"), do: gettext("Phosphate rock")
  def product_name("uranium"), do: gettext("Uranium ore")
  def product_name("wheat"), do: gettext("Wheat")
  def product_name("rice"), do: gettext("Rice")
  def product_name("sugar"), do: gettext("Cane and beet sugar")
  def product_name("palm-oil"), do: gettext("Palm oil")
  def product_name("cars"), do: gettext("Passenger cars")

  @doc "The page's title: « Le cacao en Afrique »."
  def product_title("cocoa"), do: gettext("Cocoa in Africa")
  def product_title("coffee"), do: gettext("Coffee in Africa")
  def product_title("tea"), do: gettext("Tea in Africa")
  def product_title("cashew"), do: gettext("Cashew nuts in Africa")
  def product_title("cotton"), do: gettext("Cotton in Africa")
  def product_title("rubber"), do: gettext("Natural rubber in Africa")
  def product_title("vanilla"), do: gettext("Vanilla in Africa")
  def product_title("flowers"), do: gettext("Cut flowers in Africa")
  def product_title("crude-oil"), do: gettext("Crude oil in Africa")
  def product_title("gas"), do: gettext("Natural gas in Africa")
  def product_title("gold"), do: gettext("Gold in Africa")
  def product_title("diamonds"), do: gettext("Diamonds in Africa")
  def product_title("platinum"), do: gettext("Platinum in Africa")
  def product_title("copper"), do: gettext("Copper in Africa")
  def product_title("cobalt"), do: gettext("Cobalt in Africa")
  def product_title("iron-ore"), do: gettext("Iron ore in Africa")
  def product_title("manganese"), do: gettext("Manganese in Africa")
  def product_title("phosphates"), do: gettext("Phosphates in Africa")
  def product_title("uranium"), do: gettext("Uranium in Africa")
  def product_title("wheat"), do: gettext("Wheat in Africa")
  def product_title("rice"), do: gettext("Rice in Africa")
  def product_title("sugar"), do: gettext("Sugar in Africa")
  def product_title("palm-oil"), do: gettext("Palm oil in Africa")
  def product_title("cars"), do: gettext("Cars in Africa")

  @doc "Group of a product on the index page."
  def product_group(id) when id in ~w(cocoa coffee tea cashew cotton rubber vanilla flowers),
    do: :farm

  def product_group(id) when id in ~w(crude-oil gas), do: :energy
  def product_group(id) when id in ~w(wheat rice sugar palm-oil cars), do: :bought
  def product_group(_), do: :mining

  def group_label(:farm), do: gettext("Farm products")
  def group_label(:energy), do: gettext("Energy")
  def group_label(:mining), do: gettext("Metals and minerals")
  def group_label(:bought), do: gettext("What Africa buys")

  @doc "Label of a step of a product's processing chain (HS codes of the step)."
  def step_label(["1801"]), do: gettext("Cocoa beans")
  def step_label(["1803"]), do: gettext("Cocoa paste")
  def step_label(["1804"]), do: gettext("Cocoa butter")
  def step_label(["1805"]), do: gettext("Cocoa powder")
  def step_label(["1806"]), do: gettext("Chocolate")
  def step_label(["0901"]), do: gettext("Coffee (beans, roasted)")
  def step_label(["210111", "210112"]), do: gettext("Coffee extracts and instant coffee")
  def step_label(["5201"]), do: gettext("Raw cotton")
  def step_label(["5205"]), do: gettext("Cotton yarn")
  def step_label(["5208" | _]), do: gettext("Cotton fabrics")
  def step_label(["6109"]), do: gettext("T-shirts")
  def step_label(["4001"]), do: gettext("Natural rubber")
  def step_label(["4011"]), do: gettext("Tyres")
  def step_label(["2709"]), do: gettext("Crude oil")
  def step_label(["2710"]), do: gettext("Refined products (fuel, diesel…)")
  def step_label(["2603"]), do: gettext("Copper ore")
  def step_label(["7402"]), do: gettext("Unrefined copper")
  def step_label(["7403"]), do: gettext("Refined copper (cathodes)")
  def step_label(["7408"]), do: gettext("Copper wire")
  def step_label(["8544"]), do: gettext("Insulated cables")
  def step_label(["2605"]), do: gettext("Cobalt ore")
  def step_label(["2822"]), do: gettext("Cobalt oxides and hydroxides")
  def step_label(["8105"]), do: gettext("Cobalt metal")
  def step_label(["2510"]), do: gettext("Phosphate rock")
  def step_label(["2809"]), do: gettext("Phosphoric acid")
  def step_label(["3103" | _]), do: gettext("Phosphate fertilisers")
  def step_label(["1001"]), do: gettext("Wheat")
  def step_label(["1101"]), do: gettext("Wheat flour")
  def step_label(codes), do: Enum.join(codes, ", ")

  # Shared -------------------------------------------------------------------

  defp slug(table, id, locale) do
    case List.keyfind(table, id, 0) do
      {_, fr, en, es, pt} ->
        case Locales.base(locale) do
          "fr" -> fr
          "es" -> es
          "pt" -> pt
          _ -> en
        end

      nil ->
        raise ArgumentError, "unknown trade page #{inspect(id)}"
    end
  end

  defp id_of_slug(table, slug) do
    Enum.find_value(table, fn {id, fr, en, es, pt} ->
      if slug in [fr, en, es, pt], do: id
    end)
  end

  @doc "The trade ranking of a slug in any language, or nil."
  def ranking_id(slug), do: id_of_slug(@rankings, slug)
end
