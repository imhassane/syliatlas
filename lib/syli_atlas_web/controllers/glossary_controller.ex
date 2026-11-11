defmodule SyliAtlasWeb.GlossaryController do
  @moduledoc """
  The glossary: one page per notion the site uses (GDP, purchasing power
  parity, investment grade, risk of debt distress, CFA franc…), defined in a
  few sentences, then shown with the figures of the day and the pages that
  use it. `/fr/glossaire`, `/fr/glossaire/<terme>`.
  """
  use SyliAtlasWeb, :controller

  import SyliAtlasWeb.Format, only: [value: 3]

  alias SyliAtlasWeb.{NotFoundError, Paths, PublicData, Seo, Topics}

  plug :put_layout, false

  # {id, French slug, English slug, Spanish slug, Portuguese slug}
  @terms [
    {"gdp", "pib", "gdp", "pib", "pib"},
    {"gdp_per_capita", "pib-par-habitant", "gdp-per-capita", "pib-per-capita", "pib-per-capita"},
    {"ppp", "parite-de-pouvoir-d-achat", "purchasing-power-parity",
     "paridad-de-poder-adquisitivo", "paridade-do-poder-de-compra"},
    {"real_growth", "croissance-reelle", "real-growth", "crecimiento-real", "crescimento-real"},
    {"inflation", "inflation", "inflation", "inflacion", "inflacao"},
    {"public_debt", "dette-publique", "public-debt", "deuda-publica", "divida-publica"},
    {"fiscal_balance", "solde-budgetaire", "fiscal-balance", "saldo-presupuestario",
     "saldo-orcamental"},
    {"current_account", "balance-courante", "current-account", "cuenta-corriente",
     "balanca-corrente"},
    {"sovereign_rating", "notation-souveraine", "sovereign-rating", "calificacion-soberana",
     "rating-soberano"},
    {"investment_grade", "categorie-investissement", "investment-grade", "grado-de-inversion",
     "grau-de-investimento"},
    {"default", "defaut-souverain", "sovereign-default", "impago-soberano",
     "incumprimento-soberano"},
    {"debt_distress", "risque-de-surendettement", "risk-of-debt-distress",
     "riesgo-de-sobreendeudamiento", "risco-de-sobre-endividamento"},
    {"cfa_franc", "franc-cfa", "cfa-franc", "franco-cfa", "franco-cfa"},
    {"imf_projections", "projections-du-fmi", "imf-projections", "proyecciones-del-fmi",
     "projecoes-do-fmi"}
  ]

  def terms, do: Enum.map(@terms, &elem(&1, 0))

  def index_path(locale), do: "/#{locale}/" <> Paths.segment(locale, :glossary)

  def term_path(locale, id) do
    index_path(locale) <> "/" <> SyliAtlasWeb.Topics.slug_in(List.keyfind(@terms, id, 0), locale)
  end

  defp term_id(slug), do: SyliAtlasWeb.Topics.id_of_slug(@terms, slug)

  def index(conn, _params) do
    locale = conn.assigns.locale
    paths = SyliAtlas.Locales.each(fn l -> index_path(l) end)
    title = gettext("Glossary of African economies: GDP, debt, ratings, CFA franc")
    entries = for id <- terms(), do: {name(id), short(id), term_path(locale, id)}

    render(conn, :index,
      page_title: title,
      heading: gettext("Glossary"),
      seo:
        Seo.page(
          locale,
          paths,
          gettext(
            "The notions used on Syli Atlas, each defined in a few sentences and shown with the figures of the 54 African countries."
          ),
          %{
            json_ld: [
              Seo.breadcrumbs([
                {"Syli Atlas", Paths.home(locale)},
                {gettext("Glossary"), paths[locale]}
              ]),
              term_set(locale, entries)
            ]
          }
        ),
      alternates: Seo.alternates_for_header(paths),
      entries: entries
    )
  end

  def show(conn, %{"slug" => slug}) do
    locale = conn.assigns.locale
    id = term_id(slug) || raise NotFoundError
    paths = SyliAtlas.Locales.each(fn l -> term_path(l, id) end)

    if conn.request_path != paths[locale] do
      conn |> put_status(301) |> redirect(to: paths[locale])
    else
      figures = figures(id, locale)

      render(conn, :show,
        page_title: gettext("%{term}: definition and figures for Africa", term: name(id)),
        seo:
          Seo.page(locale, paths, short(id), %{
            json_ld: [
              Seo.breadcrumbs([
                {"Syli Atlas", Paths.home(locale)},
                {gettext("Glossary"), index_path(locale)},
                {name(id), paths[locale]}
              ]),
              %{
                "@context" => "https://schema.org",
                "@type" => "DefinedTerm",
                "name" => name(id),
                "description" => short(id),
                "url" => Seo.url(paths[locale]),
                "inDefinedTermSet" => Seo.url(index_path(locale))
              }
            ]
          }),
        alternates: Seo.alternates_for_header(paths),
        id: id,
        name: name(id),
        short: short(id),
        long: long(id),
        figures: figures,
        links: links(id, locale),
        others: for(o <- terms(), o != id, do: {name(o), term_path(locale, o)})
      )
    end
  end

  defp term_set(locale, entries) do
    %{
      "@context" => "https://schema.org",
      "@type" => "DefinedTermSet",
      "name" => gettext("Glossary"),
      "url" => Seo.url(index_path(locale)),
      "hasDefinedTerm" =>
        for {n, d, p} <- entries do
          %{"@type" => "DefinedTerm", "name" => n, "description" => d, "url" => Seo.url(p)}
        end
    }
  end

  # ---------------------------------------------------------------------------
  # Words

  @doc "The term as written in the current locale."
  def name("gdp"), do: gettext("Gross domestic product (GDP)")
  def name("gdp_per_capita"), do: gettext("GDP per capita")
  def name("ppp"), do: gettext("Purchasing power parity (PPP)")
  def name("real_growth"), do: gettext("Real growth")
  def name("inflation"), do: gettext("Inflation")
  def name("public_debt"), do: gettext("Public debt")
  def name("fiscal_balance"), do: gettext("Fiscal balance")
  def name("current_account"), do: gettext("Current account balance")
  def name("sovereign_rating"), do: gettext("Sovereign credit rating")
  def name("investment_grade"), do: gettext("Investment grade")
  def name("default"), do: gettext("Sovereign default")
  def name("debt_distress"), do: gettext("Risk of debt distress")
  def name("cfa_franc"), do: gettext("CFA franc")
  def name("imf_projections"), do: gettext("IMF estimates and projections")

  @doc "One sentence: the definition people search."
  def short("gdp"),
    do:
      gettext(
        "The value of all goods and services produced in a country in a year, measured here in current US dollars."
      )

  def short("gdp_per_capita"),
    do:
      gettext(
        "GDP divided by the population: the average production per inhabitant, a measure of the level of income."
      )

  def short("ppp"),
    do:
      gettext(
        "A conversion that accounts for what money buys in each country, so that incomes can be compared in real terms."
      )

  def short("real_growth"),
    do:
      gettext(
        "The change in GDP from one year to the next once inflation is removed: what the economy really produced in addition."
      )

  def short("inflation"),
    do: gettext("The rise in consumer prices over a year, as an average annual change.")

  def short("public_debt"),
    do: gettext("What the state and other public administrations owe, in percent of GDP.")

  def short("fiscal_balance"),
    do:
      gettext(
        "Public revenue minus public spending, in percent of GDP: negative when the state spends more than it collects."
      )

  def short("current_account"),
    do:
      gettext(
        "What a country earns from abroad minus what it pays abroad (goods, services, income, transfers), in percent of GDP."
      )

  def short("sovereign_rating"),
    do:
      gettext(
        "The opinion of an agency (S&P, Moody's, Fitch) on a state's ability to repay its debt, from AAA to D."
      )

  def short("investment_grade"),
    do:
      gettext(
        "A rating of BBB− (Baa3 at Moody's) or higher: the debt is considered low risk, and most funds may buy it."
      )

  def short("default"),
    do:
      gettext(
        "When a state does not pay its creditors on time, or makes them accept a loss through a restructuring."
      )

  def short("debt_distress"),
    do:
      gettext(
        "The IMF and World Bank assessment, for low-income countries, of the risk that a state cannot service its external debt."
      )

  def short("cfa_franc"),
    do:
      gettext(
        "The two currencies shared by 14 African countries: the West African franc (XOF) and the Central African franc (XAF), both pegged to the euro."
      )

  def short("imf_projections"),
    do:
      gettext(
        "The IMF publishes its figures in April and October: the latest years are estimates, the next ones projections, revised at each edition."
      )

  @doc "A few more sentences: how to read it, what it hides."
  def long("gdp"),
    do:
      gettext(
        "In dollars, GDP also moves with the exchange rate: a fall of the currency lowers it even when the economy grows. That is why Syli Atlas shows real growth next to it. Source: IMF, World Economic Outlook."
      )

  def long("gdp_per_capita"),
    do:
      gettext(
        "An average, not what each person earns: inequality, measured by the Gini index, says how it is shared. Small countries with large oil or tourism revenues have the highest figures."
      )

  def long("ppp"),
    do:
      gettext(
        "A dollar buys more in Dakar than in New York: GDP per capita in PPP is therefore higher than at market exchange rates in most African countries. It is the better measure for comparing living standards; GDP in dollars is the better one for comparing the weight of economies."
      )

  def long("real_growth"),
    do:
      gettext(
        "A growth of 5 % means the economy produced 5 % more than the year before, at constant prices. With a population growing fast, GDP per capita grows less."
      )

  def long("inflation"),
    do:
      gettext(
        "Above 10 %, it erodes incomes and savings quickly. In the two CFA franc zones, the peg to the euro keeps it low; elsewhere it often follows the exchange rate of the currency."
      )

  def long("public_debt"),
    do:
      gettext(
        "Gross debt of the general government, as the IMF measures it. A level says little alone: its cost, its currency and its creditors (multilateral, China, bondholders) matter as much."
      )

  def long("fiscal_balance"),
    do:
      gettext(
        "A deficit is financed by debt. The WAEMU and CEMAC set a ceiling of 3 % of GDP for their members."
      )

  def long("current_account"),
    do:
      gettext(
        "A deficit means the country needs foreign financing (investment, loans, aid); a surplus, that it lends to the rest of the world. Oil exporters swing with the price of crude."
      )

  def long("sovereign_rating"),
    do:
      gettext(
        "Each agency has its scale; Syli Atlas puts them on a common scale of 22 notches (AAA = 22, BBB− = 13, D = 1) to compare countries. A rating changes the cost at which a state borrows."
      )

  def long("investment_grade"),
    do:
      gettext(
        "Below, the debt is « speculative » (BB+ and lower): the country remains solvent but borrows more expensively, and many pension funds cannot hold its bonds."
      )

  def long("default"),
    do:
      gettext(
        "Agencies then give the ratings SD, RD or D; CC and C mean a default is close. A default is followed by a restructuring negotiated with creditors, often with the IMF."
      )

  def long("debt_distress"),
    do:
      gettext(
        "Four levels: low, moderate, high, in debt distress. It covers only the countries eligible for the IMF's concessional loans; middle-income countries are not assessed."
      )

  def long("cfa_franc"),
    do:
      gettext(
        "1 euro = 655.957 francs, a fixed rate. Each zone has its central bank (BCEAO in Dakar, BEAC in Yaoundé), which sets one policy rate for all its members."
      )

  def long("imf_projections"),
    do:
      gettext(
        "Syli Atlas imports each new edition, checks it, then publishes it. Charts draw estimates and projections dashed."
      )

  # ---------------------------------------------------------------------------
  # Figures of the day: [{label, value, href}]

  defp year, do: elem(SyliAtlas.Profiles.Builder.default_period(), 1)

  defp ranking(indicator) do
    PublicData.ranking(indicator, year() - 1, year(),
      mode: "value",
      locale: Gettext.get_locale(SyliAtlasWeb.Gettext)
    )
    |> Enum.filter(&is_number(&1["value"]))
  end

  defp median(rows) do
    values = rows |> Enum.map(& &1["value"]) |> Enum.sort()
    n = length(values)

    cond do
      n == 0 -> nil
      rem(n, 2) == 1 -> Enum.at(values, div(n, 2))
      true -> (Enum.at(values, div(n, 2) - 1) + Enum.at(values, div(n, 2))) / 2
    end
  end

  defp indicator_figures(indicator, locale, first_label, last_label) do
    rows = ranking(indicator)

    case rows do
      [] ->
        []

      _ ->
        first = hd(rows)
        last = List.last(rows)
        country = fn r -> Paths.area(locale, "country", r["slug"]) end

        [
          {gettext("Median of African countries, %{year}", year: year()),
           value(median(rows), indicator, locale), Topics.ranking_path(locale, indicator)},
          {first_label <> " · " <> first["name"], value(first["value"], indicator, locale),
           country.(first)},
          {last_label <> " · " <> last["name"], value(last["value"], indicator, locale),
           country.(last)}
        ]
    end
  end

  defp figures("gdp", l),
    do: indicator_figures("gdp_usd_bn", l, gettext("Largest"), gettext("Smallest")) ++ africa(l)

  defp figures("gdp_per_capita", l),
    do: indicator_figures("gdp_per_capita_usd", l, gettext("Highest"), gettext("Lowest"))

  defp figures("ppp", l),
    do: indicator_figures("gdp_per_capita_ppp", l, gettext("Highest"), gettext("Lowest"))

  defp figures("real_growth", l),
    do: indicator_figures("real_gdp_growth", l, gettext("Fastest"), gettext("Slowest"))

  defp figures("inflation", l),
    do: indicator_figures("inflation", l, gettext("Highest"), gettext("Lowest"))

  defp figures("public_debt", l),
    do: indicator_figures("public_debt_pct_gdp", l, gettext("Highest"), gettext("Lowest"))

  defp figures("fiscal_balance", l),
    do: indicator_figures("fiscal_balance_pct_gdp", l, gettext("Highest"), gettext("Lowest"))

  defp figures("current_account", l),
    do: indicator_figures("current_account_pct_gdp", l, gettext("Highest"), gettext("Lowest"))

  defp figures(id, l) when id in ["sovereign_rating", "investment_grade", "default"] do
    case SyliAtlas.Ratings.document() do
      nil ->
        []

      doc ->
        entries = for c <- doc["ranking"], do: doc["countries"][c]
        count = fn band -> Enum.count(entries, &(&1["band"] == band)) end

        names = fn band ->
          entries
          |> Enum.filter(&(&1["band"] == band))
          |> Enum.map_join(", ", &SyliAtlas.Locales.pick(&1["name"], l))
        end

        [
          {gettext("African countries rated"), "#{doc["rated"]} / 54", Paths.ratings(l)},
          {gettext("Investment grade"), "#{count.("investment")} · #{names.("investment")}",
           Paths.ratings(l) <> "?verdict=investment"},
          {gettext("Default or close to it"), "#{count.("default")} · #{names.("default")}",
           Paths.ratings(l) <> "?verdict=default"}
        ]
    end
  end

  defp figures("debt_distress", l) do
    doc = SyliAtlas.DebtDistress.document()
    countries = Map.values(doc["countries"] || %{})

    for risk <- ~w(low moderate high distress) do
      {SyliAtlasWeb.WorldBankComponents.risk_label(risk),
       to_string(Enum.count(countries, &(&1["risk"] == risk))), Paths.debt(l)}
    end
  end

  defp figures("cfa_franc", l) do
    for code <- ~w(waemu cemac),
        c = Enum.find(SyliAtlas.Economy.Communities.all(), &(&1.code == code)),
        c do
      {SyliAtlas.Locales.pick(c.short, l) || c.short["en"],
       gettext("%{count} countries", count: length(c.members)),
       Paths.community(l, SyliAtlas.Locales.pick(c.slug, l) || c.slug["en"])}
    end
  end

  defp figures("imf_projections", l) do
    case SyliAtlas.Sources.published_edition("imf_weo") do
      nil -> []
      e -> [{gettext("Edition online"), e.label, Paths.method(l)}]
    end
  end

  defp figures(_, _), do: []

  defp africa(l) do
    case PublicData.area("africa", year() - 1, year()) do
      nil ->
        []

      d ->
        [
          {gettext("Africa, %{year}", year: year()),
           value(PublicData.at(d["profile"]["series"]["gdp_usd_bn"], year()), "gdp_usd_bn", l),
           Paths.area(l, SyliAtlas.Geo.get_area_by_code("africa"))}
        ]
    end
  end

  # Pages that use the notion.
  defp links(id, l) do
    rank = fn ind -> {Topics.ranking_title(ind, year()), Topics.ranking_path(l, ind)} end
    q = fn qid -> {Topics.question_text(qid), Topics.question_path(l, qid)} end

    case id do
      "gdp" ->
        [rank.("gdp_usd_bn"), q.("largest"), q.("africa_gdp")]

      "gdp_per_capita" ->
        [rank.("gdp_per_capita_usd"), q.("per_capita"), q.("richest")]

      "ppp" ->
        [rank.("gdp_per_capita_ppp"), rank.("gdp_per_capita_usd")]

      "real_growth" ->
        [rank.("real_gdp_growth"), q.("fastest"), q.("fastest_region")]

      "inflation" ->
        [rank.("inflation"), q.("inflation")]

      "public_debt" ->
        [
          {gettext("Debt of the 54 African countries"), Paths.debt(l)},
          rank.("public_debt_pct_gdp"),
          q.("indebted")
        ]

      "fiscal_balance" ->
        [rank.("fiscal_balance_pct_gdp"), {gettext("Economic communities"), Paths.communities(l)}]

      "current_account" ->
        [rank.("current_account_pct_gdp")]

      "sovereign_rating" ->
        [{gettext("Sovereign ratings of the 54 countries"), Paths.ratings(l)}, q.("best_rating")]

      "investment_grade" ->
        [
          q.("investment_grade"),
          {gettext("Sovereign ratings of the 54 countries"), Paths.ratings(l)}
        ]

      "default" ->
        [
          {gettext("Sovereign ratings of the 54 countries"), Paths.ratings(l)},
          {gettext("Debt of the 54 African countries"), Paths.debt(l)}
        ]

      "debt_distress" ->
        [{gettext("Debt of the 54 African countries"), Paths.debt(l)}]

      "cfa_franc" ->
        [{gettext("Economic communities"), Paths.communities(l)}]

      "imf_projections" ->
        [{gettext("Method and sources"), Paths.method(l)}]
    end
  end
end
