defmodule SyliAtlasWeb.Topics do
  @moduledoc """
  Pages written for the questions people search, each at an address of its
  own (French and English):

  - ten thematic rankings (`/fr/classement/pib`, `/en/ranking/gdp`…), one per
    IMF indicator, the value in the arrival year;
  - about sixty comparisons of two neighbours or members of one union
    (`/fr/comparer/senegal/cote-d-ivoire`): only these are indexed, not the
    free combinations of the comparator;
  - questions (`/fr/questions/pays-le-plus-riche-d-afrique`), answered in a
    sentence from the data, then the table behind it.
  """
  use Gettext, backend: SyliAtlasWeb.Gettext

  alias SyliAtlas.Geo
  alias SyliAtlasWeb.Paths

  # ---------------------------------------------------------------------------
  # Thematic rankings

  @rankings [
    {"gdp_usd_bn", "pib", "gdp", "pib", "pib"},
    {"gdp_per_capita_usd", "pib-par-habitant", "gdp-per-capita", "pib-per-capita",
     "pib-per-capita"},
    {"gdp_per_capita_ppp", "pib-par-habitant-ppa", "gdp-per-capita-ppp", "pib-per-capita-ppa",
     "pib-per-capita-ppc"},
    {"real_gdp_growth", "croissance", "growth", "crecimiento", "crescimento"},
    {"inflation", "inflation", "inflation", "inflacion", "inflacao"},
    {"public_debt_pct_gdp", "dette-publique", "public-debt", "deuda-publica", "divida-publica"},
    {"population_m", "population", "population", "poblacion", "populacao"},
    {"fiscal_balance_pct_gdp", "solde-budgetaire", "fiscal-balance", "saldo-presupuestario",
     "saldo-orcamental"},
    {"current_account_pct_gdp", "balance-courante", "current-account", "cuenta-corriente",
     "balanca-corrente"},
    {"unemployment", "chomage", "unemployment", "desempleo", "desemprego"}
  ]

  @doc "The indicators that have a ranking page."
  def ranking_indicators, do: Enum.map(@rankings, &elem(&1, 0))

  @doc "The indicator of a ranking slug (either language), or nil."
  def ranking_indicator(slug), do: id_of_slug(@rankings, slug)

  @doc "The address of an indicator's ranking."
  def ranking_path(locale, indicator) do
    case List.keyfind(@rankings, indicator, 0) do
      nil -> Paths.ranking(locale)
      entry -> Paths.ranking(locale) <> "/" <> slug_in(entry, locale)
    end
  end

  @doc "Title of a ranking page."
  def ranking_title("gdp_usd_bn", year),
    do: gettext("Ranking of African countries by GDP in %{year} (IMF)", year: year)

  def ranking_title("gdp_per_capita_usd", year),
    do: gettext("Richest African countries per person: GDP per capita %{year}", year: year)

  def ranking_title("gdp_per_capita_ppp", year),
    do:
      gettext("GDP per capita in purchasing power parity: African countries %{year}", year: year)

  def ranking_title("real_gdp_growth", year),
    do: gettext("Fastest-growing African economies in %{year} (IMF)", year: year)

  def ranking_title("inflation", year),
    do: gettext("Inflation in African countries in %{year}: the ranking", year: year)

  def ranking_title("public_debt_pct_gdp", year),
    do: gettext("Most indebted African countries in %{year}: public debt, % of GDP", year: year)

  def ranking_title("population_m", year),
    do: gettext("Most populous African countries in %{year}", year: year)

  def ranking_title("fiscal_balance_pct_gdp", year),
    do: gettext("Fiscal balance of African countries in %{year}, % of GDP", year: year)

  def ranking_title("current_account_pct_gdp", year),
    do: gettext("Current account balance of African countries in %{year}, % of GDP", year: year)

  def ranking_title("unemployment", year),
    do: gettext("Unemployment in African countries in %{year}", year: year)

  def ranking_title(_, year), do: gettext("Ranking of African economies in %{year}", year: year)

  # ---------------------------------------------------------------------------
  # Pairs of countries

  # Every pair within the two monetary unions, then neighbours and rivals
  # people compare (codes in the order of the address).
  @extra_pairs [
    ~w(NGA ZAF),
    ~w(NGA EGY),
    ~w(EGY ZAF),
    ~w(MAR DZA),
    ~w(MAR TUN),
    ~w(DZA TUN),
    ~w(KEN ETH),
    ~w(KEN TZA),
    ~w(KEN UGA),
    ~w(TZA UGA),
    ~w(GHA CIV),
    ~w(NGA GHA),
    ~w(RWA BDI),
    ~w(ZMB ZWE),
    ~w(BWA NAM),
    ~w(AGO COD),
    ~w(EGY ETH),
    ~w(MOZ TZA),
    ~w(GIN SEN)
  ]

  @doc "The pairs with an indexed comparison page, as [code, code]."
  def pairs do
    unions =
      for code <- ~w(waemu cemac),
          c = Enum.find(SyliAtlas.Economy.Communities.all(), &(&1.code == code)),
          c != nil,
          members = Enum.sort(c.members),
          {a, i} <- Enum.with_index(members),
          b <- Enum.drop(members, i + 1),
          do: [a, b]

    Enum.uniq_by(unions ++ @extra_pairs, &Enum.sort/1)
  end

  @doc "The pair of `codes` in its address order, or nil if it has no page."
  def pair(codes) do
    sorted = Enum.sort(codes)
    Enum.find(pairs(), &(Enum.sort(&1) == sorted))
  end

  @doc "The address of a pair's comparison."
  def pair_path(locale, [a, b]) do
    slug = fn code -> Geo.Area.slug(Geo.get_area_by_code(code), locale) end
    Paths.compare(locale, [slug.(a), slug.(b)])
  end

  # ---------------------------------------------------------------------------
  # Questions

  @questions [
    {"richest", "pays-le-plus-riche-d-afrique", "richest-country-in-africa",
     "pais-mas-rico-de-africa", "pais-mais-rico-de-africa"},
    {"largest", "plus-grandes-economies-d-afrique", "largest-economies-in-africa",
     "mayores-economias-de-africa", "maiores-economias-de-africa"},
    {"per_capita", "pays-africains-les-plus-riches-par-habitant",
     "richest-african-countries-per-person", "paises-africanos-mas-ricos-por-habitante",
     "paises-africanos-mais-ricos-por-habitante"},
    {"fastest", "economies-africaines-qui-croissent-le-plus-vite",
     "fastest-growing-african-economies", "economias-africanas-que-mas-crecen",
     "economias-africanas-que-mais-crescem"},
    {"indebted", "pays-africains-les-plus-endettes", "most-indebted-african-countries",
     "paises-africanos-mas-endeudados", "paises-africanos-mais-endividados"},
    {"inflation", "inflation-la-plus-elevee-d-afrique", "highest-inflation-in-africa",
     "inflacion-mas-alta-de-africa", "inflacao-mais-alta-de-africa"},
    {"populous", "pays-le-plus-peuple-d-afrique", "most-populous-country-in-africa",
     "pais-mas-poblado-de-africa", "pais-mais-populoso-de-africa"},
    {"africa_gdp", "pib-de-l-afrique", "gdp-of-africa", "pib-de-africa", "pib-de-africa"},
    {"fastest_region", "region-d-afrique-qui-croit-le-plus-vite",
     "fastest-growing-region-of-africa", "region-de-africa-que-mas-crece",
     "regiao-de-africa-que-mais-cresce"},
    {"investment_grade", "pays-africains-en-categorie-investissement",
     "investment-grade-african-countries", "paises-africanos-con-grado-de-inversion",
     "paises-africanos-com-grau-de-investimento"},
    {"best_rating", "meilleure-note-souveraine-d-afrique", "best-credit-rating-in-africa",
     "mejor-calificacion-soberana-de-africa", "melhor-rating-soberano-de-africa"},
    {"largest_community", "plus-grande-communaute-economique-d-afrique",
     "largest-economic-community-in-africa", "mayor-comunidad-economica-de-africa",
     "maior-comunidade-economica-de-africa"}
  ]

  @doc "The questions, as ids."
  def questions, do: Enum.map(@questions, &elem(&1, 0))

  @doc "The question id of a slug (either language), or nil."
  def question(slug), do: id_of_slug(@questions, slug)

  def questions_path(locale), do: "/#{locale}/" <> Paths.segment(locale, :questions)

  def question_path(locale, id),
    do: questions_path(locale) <> "/" <> slug_in(List.keyfind(@questions, id, 0), locale)

  # ---------------------------------------------------------------------------
  # Slug tables: {id, French, English, Spanish, Portuguese}

  @doc "The slug of a table entry in a language (Arabic, Hindi, Chinese: English)."
  def slug_in({_id, fr, en, es, pt}, locale) do
    case SyliAtlas.Locales.base(locale) do
      "fr" -> fr
      "es" -> es
      "pt" -> pt
      _ -> en
    end
  end

  @doc "The id of a slug in any language of a table, or nil."
  def id_of_slug(table, slug) do
    Enum.find_value(table, fn {id, fr, en, es, pt} -> if slug in [fr, en, es, pt], do: id end)
  end

  @doc "The question itself, as people ask it."
  def question_text("richest"), do: gettext("What is the richest country in Africa?")
  def question_text("largest"), do: gettext("What are the largest economies in Africa?")
  def question_text("per_capita"), do: gettext("Which African countries are richest per person?")
  def question_text("fastest"), do: gettext("Which African economies are growing fastest?")
  def question_text("indebted"), do: gettext("Which African countries are most in debt?")

  def question_text("inflation"),
    do: gettext("Which African countries have the highest inflation?")

  def question_text("populous"), do: gettext("What is the most populous country in Africa?")
  def question_text("africa_gdp"), do: gettext("What is the GDP of Africa?")
  def question_text("fastest_region"), do: gettext("Which region of Africa is growing fastest?")

  def question_text("investment_grade"),
    do: gettext("Which African countries are investment grade?")

  def question_text("best_rating"),
    do: gettext("Which African country has the best credit rating?")

  def question_text("largest_community"),
    do: gettext("What is the largest economic community in Africa?")

  # ---------------------------------------------------------------------------

  @doc "Pages of this module for the sitemap: %{\"fr\" => path, \"en\" => path}."
  def sitemap_pages do
    both = &SyliAtlas.Locales.each/1

    for(i <- ranking_indicators(), do: both.(&ranking_path(&1, i))) ++
      [both.(&questions_path/1)] ++
      for(q <- questions(), do: both.(&question_path(&1, q))) ++
      for(p <- pairs(), do: both.(&pair_path(&1, p))) ++
      [both.(&Paths.about/1)] ++
      [both.(&SyliAtlasWeb.GlossaryController.index_path/1)] ++
      for(
        t <- SyliAtlasWeb.GlossaryController.terms(),
        do: both.(&SyliAtlasWeb.GlossaryController.term_path(&1, t))
      )
  end
end
