defmodule SyliAtlasWeb.Api.Catalog do
  @moduledoc """
  The dictionary of the public API: what each indicator measures and in
  which unit, and every closed list of values (area kinds, regions, year
  statuses, units, ranking modes), in French and English.

  One source for the answers (`/api/v1/indicators`, `/api/v1`), the
  OpenAPI document (`SyliAtlasWeb.Api.Spec`) and the documentation page:
  they cannot disagree.
  """
  alias SyliAtlas.Sources.Indicators

  @indicators [
    %{
      key: "real_gdp_index",
      name: %{fr: "PIB réel (indice)", en: "Real GDP (index)"},
      unit: "index_2015",
      description: %{
        fr:
          "Volume du PIB, 100 en 2015, obtenu en enchaînant les taux de croissance réelle du FMI. Calcul Syli Atlas.",
        en:
          "GDP volume, 100 in 2015, chained from the IMF real growth rates. Computed by Syli Atlas."
      }
    },
    %{
      key: "real_gdp_growth",
      name: %{fr: "Croissance du PIB réel", en: "Real GDP growth"},
      unit: "percent",
      description: %{
        fr: "Variation annuelle du PIB à prix constants.",
        en: "Annual change of GDP at constant prices."
      }
    },
    %{
      key: "gdp_usd_bn",
      name: %{fr: "PIB en dollars courants", en: "GDP, current dollars"},
      unit: "usd_billion",
      description: %{
        fr: "Produit intérieur brut aux prix courants, converti en dollars US.",
        en: "Gross domestic product at current prices, in US dollars."
      }
    },
    %{
      key: "gdp_per_capita_usd",
      name: %{fr: "PIB par habitant", en: "GDP per capita"},
      unit: "usd",
      description: %{
        fr: "PIB en dollars courants divisé par la population.",
        en: "GDP in current dollars divided by the population."
      }
    },
    %{
      key: "gdp_per_capita_ppp",
      name: %{fr: "PIB par habitant en PPA", en: "GDP per capita, PPP"},
      unit: "intl_dollar",
      description: %{
        fr:
          "PIB par habitant en parité de pouvoir d'achat (dollars internationaux courants) : compare les niveaux de vie.",
        en:
          "GDP per capita at purchasing power parity (current international dollars): compares living standards."
      }
    },
    %{
      key: "inflation",
      name: %{fr: "Inflation", en: "Inflation"},
      unit: "percent",
      description: %{
        fr: "Variation annuelle moyenne des prix à la consommation.",
        en: "Average annual change of consumer prices."
      }
    },
    %{
      key: "public_debt_pct_gdp",
      name: %{fr: "Dette publique", en: "Public debt"},
      unit: "percent_of_gdp",
      description: %{
        fr: "Dette brute des administrations publiques, en % du PIB.",
        en: "General government gross debt, as % of GDP."
      }
    },
    %{
      key: "population_m",
      name: %{fr: "Population", en: "Population"},
      unit: "million_people",
      description: %{fr: "Population totale.", en: "Total population."}
    },
    %{
      key: "fiscal_balance_pct_gdp",
      name: %{fr: "Solde budgétaire", en: "Fiscal balance"},
      unit: "percent_of_gdp",
      description: %{
        fr:
          "Capacité (+) ou besoin (−) de financement des administrations publiques, en % du PIB.",
        en: "General government net lending (+) or borrowing (−), as % of GDP."
      }
    },
    %{
      key: "current_account_pct_gdp",
      name: %{fr: "Balance courante", en: "Current account"},
      unit: "percent_of_gdp",
      description: %{
        fr: "Solde des échanges de biens, services et revenus avec l'extérieur, en % du PIB.",
        en: "Balance of trade in goods, services and income with the world, as % of GDP."
      }
    },
    %{
      key: "unemployment",
      name: %{fr: "Chômage", en: "Unemployment"},
      unit: "percent_of_labour_force",
      description: %{
        fr: "Chômeurs en % de la population active. Le FMI ne le publie pas pour tous les pays.",
        en: "Unemployed as % of the labour force. The IMF does not publish it for every country."
      }
    }
  ]

  @units [
    {"percent", "%", "%"},
    {"percent_of_gdp", "% du PIB", "% of GDP"},
    {"percent_of_labour_force", "% de la population active", "% of the labour force"},
    {"usd_billion", "milliards de dollars US courants", "billions of current US dollars"},
    {"usd", "dollars US courants", "current US dollars"},
    {"intl_dollar", "dollars internationaux courants (PPA)",
     "current international dollars (PPP)"},
    {"million_people", "millions d'habitants", "millions of people"},
    {"index_2015", "indice, 100 en 2015", "index, 100 in 2015"},
    {"points", "points de pourcentage", "percentage points"}
  ]

  @kinds [
    {"country", "Un des 54 pays africains.", "One of the 54 African countries."},
    {"region", "Une des 5 régions de l'Union africaine ; totaux calculés par Syli Atlas.",
     "One of the 5 African Union regions; totals computed by Syli Atlas."},
    {"continent", "L'Afrique entière ; totaux calculés par Syli Atlas.",
     "Africa as a whole; totals computed by Syli Atlas."},
    {"imf_aggregate",
     "Un agrégat publié tel quel par le FMI : le Monde, l'Afrique subsaharienne.",
     "An aggregate published as is by the IMF: the World, sub-Saharan Africa."}
  ]

  @statuses [
    {"actual", "Valeur observée.", "Observed value."},
    {"estimate",
     "Estimation du FMI : l'année est finie mais les chiffres ne sont pas définitifs.",
     "IMF estimate: the year is over but the figures are not final."},
    {"projection", "Projection du FMI.", "IMF projection."}
  ]

  @modes [
    {"change", "Variation entre from et to.", "Change between from and to."},
    {"value", "Valeur de l'année to.", "Value in the year to."}
  ]

  @doc "Every published indicator, in the order of the series."
  def indicators do
    for i <- @indicators do
      meta = Indicators.get(i.key)

      Map.merge(i, %{
        kind: Atom.to_string(meta.kind),
        change_unit: change_unit(i.key),
        imf_code: meta.imf
      })
    end
  end

  @doc "The keys of the published indicators, in the order of the series."
  def indicator_keys, do: Enum.map(@indicators, & &1.key)

  @doc """
  The unit of a change: rates (already in %) change in percentage points,
  levels and the index in percent.
  """
  def change_unit(key) do
    case Indicators.get(key) do
      %{kind: :rate} -> "points"
      _ -> "percent"
    end
  end

  @doc "The unit of an indicator's values."
  def unit(key), do: Enum.find_value(@indicators, &(&1.key == key && &1.unit))

  def units,
    do: Enum.map(@units, fn {code, fr, en} -> %{code: code, label: %{fr: fr, en: en}} end)

  def unit_codes, do: Enum.map(@units, &elem(&1, 0))

  def kinds, do: values(@kinds)
  def statuses, do: values(@statuses)
  def modes, do: values(@modes)

  def regions do
    names = %{
      "north_africa" => {"Afrique du Nord", "North Africa"},
      "west_africa" => {"Afrique de l'Ouest", "West Africa"},
      "central_africa" => {"Afrique centrale", "Central Africa"},
      "east_africa" => {"Afrique de l'Est", "East Africa"},
      "southern_africa" => {"Afrique australe", "Southern Africa"}
    }

    for code <- SyliAtlas.Geo.regions() do
      {fr, en} = names[code]
      %{code: code, label: %{fr: fr, en: en}}
    end
  end

  @doc "Codes only, for the schema's enums."
  def codes(list), do: Enum.map(list, & &1.code)

  defp values(list),
    do: Enum.map(list, fn {code, fr, en} -> %{code: code, label: %{fr: fr, en: en}} end)
end
