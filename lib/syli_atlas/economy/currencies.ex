defmodule SyliAtlas.Economy.Currencies do
  @moduledoc """
  The currency of each African country (ISO 4217 code) and, when it has
  one, its fixed peg.

  Only pegs set by treaty or by the central bank are listed: the CFA francs
  and their sisters tied to the euro, the currencies of the Common Monetary
  Area at par with the rand, and two currencies tied to the dollar. Every
  other currency is shown without a regime: floating and managed regimes
  change, and the page would go stale silently.
  """

  # {code, name fr, name en}
  @currencies %{
    "DZA" => {"DZD", "dinar algérien", "Algerian dinar"},
    "AGO" => {"AOA", "kwanza", "kwanza"},
    "BEN" => {"XOF", "franc CFA (UEMOA)", "West African CFA franc"},
    "BWA" => {"BWP", "pula", "pula"},
    "BFA" => {"XOF", "franc CFA (UEMOA)", "West African CFA franc"},
    "BDI" => {"BIF", "franc burundais", "Burundian franc"},
    "CPV" => {"CVE", "escudo cap-verdien", "Cape Verdean escudo"},
    "CMR" => {"XAF", "franc CFA (CEMAC)", "Central African CFA franc"},
    "CAF" => {"XAF", "franc CFA (CEMAC)", "Central African CFA franc"},
    "TCD" => {"XAF", "franc CFA (CEMAC)", "Central African CFA franc"},
    "COM" => {"KMF", "franc comorien", "Comorian franc"},
    "COD" => {"CDF", "franc congolais", "Congolese franc"},
    "COG" => {"XAF", "franc CFA (CEMAC)", "Central African CFA franc"},
    "CIV" => {"XOF", "franc CFA (UEMOA)", "West African CFA franc"},
    "DJI" => {"DJF", "franc djiboutien", "Djiboutian franc"},
    "EGY" => {"EGP", "livre égyptienne", "Egyptian pound"},
    "GNQ" => {"XAF", "franc CFA (CEMAC)", "Central African CFA franc"},
    "ERI" => {"ERN", "nakfa", "nakfa"},
    "SWZ" => {"SZL", "lilangeni", "lilangeni"},
    "ETH" => {"ETB", "birr", "birr"},
    "GAB" => {"XAF", "franc CFA (CEMAC)", "Central African CFA franc"},
    "GMB" => {"GMD", "dalasi", "dalasi"},
    "GHA" => {"GHS", "cedi", "cedi"},
    "GIN" => {"GNF", "franc guinéen", "Guinean franc"},
    "GNB" => {"XOF", "franc CFA (UEMOA)", "West African CFA franc"},
    "KEN" => {"KES", "shilling kényan", "Kenyan shilling"},
    "LSO" => {"LSL", "loti", "loti"},
    "LBR" => {"LRD", "dollar libérien", "Liberian dollar"},
    "LBY" => {"LYD", "dinar libyen", "Libyan dinar"},
    "MDG" => {"MGA", "ariary", "ariary"},
    "MWI" => {"MWK", "kwacha malawite", "Malawian kwacha"},
    "MLI" => {"XOF", "franc CFA (UEMOA)", "West African CFA franc"},
    "MRT" => {"MRU", "ouguiya", "ouguiya"},
    "MUS" => {"MUR", "roupie mauricienne", "Mauritian rupee"},
    "MAR" => {"MAD", "dirham marocain", "Moroccan dirham"},
    "MOZ" => {"MZN", "metical", "metical"},
    "NAM" => {"NAD", "dollar namibien", "Namibian dollar"},
    "NER" => {"XOF", "franc CFA (UEMOA)", "West African CFA franc"},
    "NGA" => {"NGN", "naira", "naira"},
    "RWA" => {"RWF", "franc rwandais", "Rwandan franc"},
    "STP" => {"STN", "dobra", "dobra"},
    "SEN" => {"XOF", "franc CFA (UEMOA)", "West African CFA franc"},
    "SYC" => {"SCR", "roupie seychelloise", "Seychellois rupee"},
    "SLE" => {"SLE", "leone", "leone"},
    "SOM" => {"SOS", "shilling somalien", "Somali shilling"},
    "ZAF" => {"ZAR", "rand", "rand"},
    "SSD" => {"SSP", "livre sud-soudanaise", "South Sudanese pound"},
    "SDN" => {"SDG", "livre soudanaise", "Sudanese pound"},
    "TZA" => {"TZS", "shilling tanzanien", "Tanzanian shilling"},
    "TGO" => {"XOF", "franc CFA (UEMOA)", "West African CFA franc"},
    "TUN" => {"TND", "dinar tunisien", "Tunisian dinar"},
    "UGA" => {"UGX", "shilling ougandais", "Ugandan shilling"},
    "ZMB" => {"ZMW", "kwacha zambien", "Zambian kwacha"},
    "ZWE" => {"ZWG", "zimbabwe gold (ZiG)", "Zimbabwe Gold (ZiG)"}
  }

  # Fixed pegs: {anchor currency, units of the local currency per anchor unit}.
  @pegs %{
    "XOF" => {"EUR", 655.957},
    "XAF" => {"EUR", 655.957},
    "KMF" => {"EUR", 491.96775},
    "CVE" => {"EUR", 110.265},
    "STN" => {"EUR", 24.5},
    "DJF" => {"USD", 177.721},
    "ERN" => {"USD", 15.0},
    "LSL" => {"ZAR", 1.0},
    "NAD" => {"ZAR", 1.0},
    "SZL" => {"ZAR", 1.0}
  }

  @zones %{
    "uemoa" => ~w(BEN BFA CIV GNB MLI NER SEN TGO),
    "cemac" => ~w(CMR CAF TCD COG GNQ GAB),
    "cma" => ~w(ZAF LSO NAM SWZ)
  }

  @external_resource "priv/data/currency_names.json"
  @names "priv/data/currency_names.json" |> File.read!() |> Jason.decode!() |> Map.delete("_note")

  defp name(_code, fr, _en, "fr"), do: fr
  defp name(_code, _fr, en, "en"), do: en
  defp name(code, _fr, en, locale), do: get_in(@names, [code, locale]) || en

  @doc """
  The currency of a country, or nil:
  `%{code, name, peg: nil | %{anchor, rate}, zone: nil | "uemoa" | "cemac" | "cma", partners}`.
  """
  def for_country(country_code, locale \\ "fr") do
    case Map.fetch(@currencies, country_code) do
      {:ok, {code, fr, en}} ->
        zone = zone(country_code)

        %{
          code: code,
          name: name(code, fr, en, locale),
          peg:
            case Map.fetch(@pegs, code) do
              {:ok, {anchor, rate}} -> %{anchor: anchor, rate: rate}
              :error -> nil
            end,
          zone: zone,
          partners: if(zone, do: Map.fetch!(@zones, zone) -- [country_code], else: [])
        }

      :error ->
        nil
    end
  end

  @doc "The monetary union or area of a country, or nil."
  def zone(country_code) do
    Enum.find_value(@zones, fn {zone, members} -> if country_code in members, do: zone end)
  end

  def zone_members(zone), do: Map.fetch!(@zones, zone)
  def countries, do: Map.keys(@currencies)
end
