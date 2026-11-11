defmodule SyliAtlasWeb.CountryQuestionsController do
  @moduledoc """
  `/fr/pays/<pays>/questions`: the questions people ask about one country's
  economy, each answered in a sentence from the data of the day (IMF, World
  Bank, CEPII, rating agencies, IMF-World Bank debt analyses), with the page
  that goes further. A question is asked only when the data answers it.
  """
  use SyliAtlasWeb, :controller

  import SyliAtlasWeb.Format, only: [value: 3, number: 3, names: 2]

  alias SyliAtlas.Geo
  alias SyliAtlas.Geo.Area
  alias SyliAtlasWeb.{NotFoundError, Paths, PublicData, Seo, Topics}

  plug :put_layout, false

  def show(conn, %{"slug" => slug}) do
    locale = conn.assigns.locale
    area = Geo.get_area_by_slug(slug, locale)
    if is_nil(area) or area.kind != "country", do: raise(NotFoundError)

    paths = SyliAtlas.Locales.each(fn l -> questions_path(l, area) end)

    if conn.request_path != paths[locale] do
      conn |> put_status(301) |> redirect(to: paths[locale])
    else
      name = Area.name(area, locale)
      items = questions(area, locale)
      if items == [], do: raise(NotFoundError)

      title =
        gettext(
          "%{name}: %{count} questions on the economy, answered",
          names(name, count: length(items))
        )

      render(conn, :show,
        page_title: title,
        seo:
          Seo.page(locale, paths, hd(items).answer, %{
            json_ld: [
              Seo.breadcrumbs([
                {"Syli Atlas", Paths.home(locale)},
                {name, Paths.area(locale, area)},
                {gettext("Questions"), paths[locale]}
              ]),
              Seo.faq(for(q <- items, do: {q.question, q.answer}))
            ]
          }),
        alternates: Seo.alternates_for_header(paths),
        area: area,
        name: name,
        heading: gettext("Questions on the economy of %{name}", names(name, [])),
        items: items
      )
    end
  end

  @doc "The address of a country's questions."
  def questions_path(locale, area),
    do: Paths.area(locale, area) <> "/" <> Paths.segment(locale, :questions)

  # ---------------------------------------------------------------------------

  @doc """
  The questions on `area`, as `%{id, question, answer, href}`, in reading
  order. Each builder returns nil when the data does not answer.
  """
  def questions(area, locale) do
    {from, to} = SyliAtlas.Profiles.Builder.default_period()

    case PublicData.area(area.code, from, to) do
      nil ->
        []

      data ->
        ctx = %{
          area: area,
          code: area.code,
          locale: locale,
          name: Area.name(area, locale),
          data: data,
          s: data["profile"]["series"],
          from: from,
          to: to,
          rating_doc: SyliAtlas.Ratings.document()
        }

        [
          &gdp/1,
          &growth/1,
          &projection/1,
          &rich/1,
          &population/1,
          &inflation/1,
          &debt/1,
          &default/1,
          &rating/1,
          &currency/1,
          &exports/1,
          &communities/1,
          &exchange/1,
          &electricity/1
        ]
        |> Enum.map(fn f ->
          try do
            f.(ctx)
          rescue
            _ -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)
    end
  end

  defp at(ctx, key, year \\ nil), do: PublicData.at(ctx.s[key], year || ctx.to)

  defp tab(ctx, tab), do: Paths.area_tab(ctx.locale, ctx.area, tab)

  # Rank of the country and median of Africa for an indicator in `to`.
  defp standing(ctx, indicator) do
    rows =
      PublicData.ranking(indicator, ctx.to - 1, ctx.to, mode: "value")
      |> Enum.filter(&is_number(&1["value"]))

    values = rows |> Enum.map(& &1["value"]) |> Enum.sort()
    n = length(values)

    median =
      cond do
        n == 0 -> nil
        rem(n, 2) == 1 -> Enum.at(values, div(n, 2))
        true -> (Enum.at(values, div(n, 2) - 1) + Enum.at(values, div(n, 2))) / 2
      end

    rank =
      case Enum.find_index(rows, &(&1["code"] == ctx.code)) do
        nil -> nil
        i -> i + 1
      end

    %{rank: rank, of: n, median: median}
  end

  defp q(id, question, answer, href),
    do: %{id: id, question: question, answer: answer, href: href}

  defp v(ctx, x, indicator), do: value(x, indicator, ctx.locale)

  defp gdp(ctx) do
    gdp = at(ctx, "gdp_usd_bn")
    st = standing(ctx, "gdp_usd_bn")

    if gdp && st.rank do
      q(
        "gdp",
        gettext("What is the GDP of %{name}?", names(ctx.name, [])),
        gettext(
          "%{gdp} in %{year} (IMF, current dollars): no. %{rank} of %{of} African economies.",
          gdp: v(ctx, gdp, "gdp_usd_bn"),
          year: ctx.to,
          rank: st.rank,
          of: st.of
        ),
        tab(ctx, :economy)
      )
    end
  end

  defp growth(ctx) do
    g = at(ctx, "real_gdp_growth")
    next = at(ctx, "real_gdp_growth", ctx.to + 1)

    if g do
      q(
        "growth",
        gettext("What is the economic growth of %{name}?", names(ctx.name, [])),
        gettext("Real GDP growth of %{growth} in %{year} (IMF estimate).",
          growth: v(ctx, g, "real_gdp_growth"),
          year: ctx.to
        ) <>
          if(next,
            do:
              " " <>
                gettext("The IMF projects %{growth} for %{year}.",
                  growth: v(ctx, next, "real_gdp_growth"),
                  year: ctx.to + 1
                ),
            else: ""
          ),
        tab(ctx, :economy)
      )
    end
  end

  defp projection(ctx) do
    last = SyliAtlas.Sources.Indicators.last_year()
    gdp_last = at(ctx, "gdp_usd_bn", last)
    gdp_now = at(ctx, "gdp_usd_bn")
    idx_now = at(ctx, "real_gdp_index")
    idx_last = at(ctx, "real_gdp_index", last)

    if gdp_last && gdp_now && idx_now && idx_last do
      years = last - ctx.to
      avg = (:math.pow(idx_last / idx_now, 1 / years) - 1) * 100

      q(
        "projection",
        gettext(
          "What GDP does the IMF project for %{name} in %{year}?",
          names(ctx.name, year: last)
        ),
        gettext(
          "%{gdp} in %{year} according to the IMF projections, against %{now} in %{to}: real growth of %{avg} a year on average.",
          gdp: v(ctx, gdp_last, "gdp_usd_bn"),
          year: last,
          now: v(ctx, gdp_now, "gdp_usd_bn"),
          to: ctx.to,
          avg: number(avg, 1, ctx.locale) <> " %"
        ),
        tab(ctx, :economy)
      )
    end
  end

  defp rich(ctx) do
    pc = at(ctx, "gdp_per_capita_usd")
    st = standing(ctx, "gdp_per_capita_usd")

    if pc && st.median && st.rank do
      ratio = pc / st.median

      verdict =
        cond do
          ratio >= 2 -> gettext("well above the African median")
          ratio >= 1.15 -> gettext("above the African median")
          ratio > 0.87 -> gettext("close to the African median")
          ratio > 0.5 -> gettext("below the African median")
          true -> gettext("far below the African median")
        end

      q(
        "rich",
        gettext("Is %{name} a rich country?", names(ctx.name, [])),
        gettext(
          "GDP per capita of %{value} in %{year}, %{verdict} (%{median}): no. %{rank} of %{of} in Africa per person (IMF).",
          value: v(ctx, pc, "gdp_per_capita_usd"),
          year: ctx.to,
          verdict: verdict,
          median: v(ctx, st.median, "gdp_per_capita_usd"),
          rank: st.rank,
          of: st.of
        ),
        Topics.ranking_path(ctx.locale, "gdp_per_capita_usd")
      )
    end
  end

  defp population(ctx) do
    pop = at(ctx, "population_m")
    st = standing(ctx, "population_m")

    if pop && st.rank do
      q(
        "population",
        gettext("How many people live in %{name}?", names(ctx.name, [])),
        gettext("%{value} inhabitants in %{year} (IMF): no. %{rank} in Africa by population.",
          value: v(ctx, pop, "population_m"),
          year: ctx.to,
          rank: st.rank
        ),
        Topics.ranking_path(ctx.locale, "population_m")
      )
    end
  end

  defp inflation(ctx) do
    i = at(ctx, "inflation")
    next = at(ctx, "inflation", ctx.to + 1)

    if i do
      q(
        "inflation",
        gettext("What is the inflation rate in %{name}?", names(ctx.name, [])),
        gettext("%{value} in %{year}, average annual change in consumer prices (IMF).",
          value: v(ctx, i, "inflation"),
          year: ctx.to
        ) <>
          if(next,
            do:
              " " <>
                gettext("Projection for %{year}: %{value}.",
                  year: ctx.to + 1,
                  value: v(ctx, next, "inflation")
                ),
            else: ""
          ),
        tab(ctx, :finances)
      )
    end
  end

  defp debt(ctx) do
    d = at(ctx, "public_debt_pct_gdp")
    st = standing(ctx, "public_debt_pct_gdp")

    if d && st.median do
      q(
        "debt",
        gettext("Is %{name} highly indebted?", names(ctx.name, [])),
        gettext(
          "Public debt of %{value} of GDP in %{year}, against a median of %{median} in Africa: no. %{rank} of %{of} from the most indebted (IMF).",
          value: v(ctx, d, "public_debt_pct_gdp"),
          year: ctx.to,
          median: v(ctx, st.median, "public_debt_pct_gdp"),
          rank: st.rank,
          of: st.of
        ),
        tab(ctx, :finances)
      )
    end
  end

  defp default(ctx) do
    entry = SyliAtlas.Ratings.for_country(ctx.rating_doc, ctx.code)
    distress = SyliAtlas.DebtDistress.for_country(ctx.code)
    band = entry && entry["band"]
    risk = distress && distress["risk"]

    if band || risk do
      agencies = entry && SyliAtlasWeb.RatingComponents.agencies_text(entry)

      answer =
        cond do
          band == "default" ->
            gettext(
              "The agencies consider %{name} in default or close to it: %{agencies}. A restructuring of the debt, with losses for creditors, is expected.",
              names(ctx.name, agencies: agencies)
            )

          risk == "distress" ->
            gettext(
              "The IMF and the World Bank consider %{name} in debt distress (analysis of %{date}): it struggles to pay its creditors.",
              names(ctx.name,
                date: SyliAtlasWeb.RatingComponents.date_text(distress["published"], ctx.locale)
              )
            )

          band ->
            gettext("No. Its rating is %{rating} (%{agencies}).",
              rating: entry["label"],
              agencies: agencies
            ) <>
              if(risk,
                do:
                  " " <>
                    gettext("Risk of debt distress: %{risk} (IMF-World Bank, %{date}).",
                      risk: String.downcase(SyliAtlasWeb.WorldBankComponents.risk_label(risk)),
                      date:
                        SyliAtlasWeb.RatingComponents.date_text(distress["published"], ctx.locale)
                    ),
                else: ""
              )

          true ->
            gettext(
              "No rating agency rates it; the IMF and the World Bank put its risk of debt distress at « %{risk} » (%{date}).",
              risk: String.downcase(SyliAtlasWeb.WorldBankComponents.risk_label(risk)),
              date: SyliAtlasWeb.RatingComponents.date_text(distress["published"], ctx.locale)
            )
        end

      q(
        "default",
        gettext("Is %{name} in default?", names(ctx.name, [])),
        answer,
        tab(ctx, :finances)
      )
    end
  end

  defp rating(ctx) do
    entry = SyliAtlas.Ratings.for_country(ctx.rating_doc, ctx.code)

    if entry && entry["band"] do
      q(
        "rating",
        gettext("What is the credit rating of %{name}?", names(ctx.name, [])),
        gettext("%{agencies}: %{verdict}, no. %{rank} of the %{of} African countries rated.",
          agencies: SyliAtlasWeb.RatingComponents.agencies_text(entry),
          verdict: String.downcase(SyliAtlasWeb.RatingComponents.verdict(entry["band"])),
          rank: entry["rank"],
          of: ctx.rating_doc["rated"]
        ),
        Paths.rating(ctx.locale, Area.slug(ctx.area, ctx.locale))
      )
    end
  end

  defp currency(ctx) do
    with %{name: name, code: code} = c <-
           SyliAtlas.Economy.Currencies.for_country(ctx.code, ctx.locale) do
      peg =
        case c.peg do
          %{anchor: anchor, rate: rate} ->
            " " <>
              gettext("Fixed rate: %{rate} %{code} for 1 %{anchor}.",
                anchor: anchor,
                rate: number(rate * 1.0, if(rate < 10, do: 2, else: 3), ctx.locale),
                code: code
              )

          _ ->
            ""
        end

      q(
        "currency",
        gettext("What is the currency of %{name}?", names(ctx.name, [])),
        gettext("Its currency: %{currency} (%{code}).", currency: name, code: code) <> peg,
        tab(ctx, :finances) <> "#monnaie"
      )
    end
  end

  defp exports(ctx) do
    doc = SyliAtlas.Trade.document()
    t = SyliAtlas.Trade.for_country(ctx.code)

    with %{"top_exports" => [_ | _] = top} <- t do
      products =
        top
        |> Enum.take(3)
        |> Enum.map_join(", ", fn e ->
          "#{SyliAtlasWeb.TradeComponents.chapter(doc, e["chapter"], ctx.locale)} (#{number(e["share"], 1, ctx.locale)} %)"
        end)

      client =
        case t["top_clients"] do
          [c | _] -> SyliAtlasWeb.TradeComponents.partner(doc, c["code"], ctx.locale)
          _ -> nil
        end

      q(
        "exports",
        gettext("What does %{name} export?", names(ctx.name, [])),
        gettext("In %{year}, mostly: %{products}. First client: %{client} (CEPII, BACI).",
          year: doc["year"],
          products: products,
          client: client || "—"
        ),
        tab(ctx, :trade)
      )
    end
  end

  defp communities(ctx) do
    case SyliAtlas.Economy.Communities.for_country(ctx.code) do
      [] ->
        nil

      list ->
        q(
          "communities",
          gettext("Which economic communities is %{name} part of?", names(ctx.name, [])),
          Enum.map_join(
            list,
            ", ",
            &"#{&1.short[ctx.locale] || &1.short["en"]} (#{&1.name[ctx.locale] || &1.name["en"]})"
          ) <> ".",
          Paths.community(ctx.locale, hd(list).slug[ctx.locale] || hd(list).slug["en"])
        )
    end
  end

  defp exchange(ctx) do
    with true <- SyliAtlas.Market.public?(), [x | _] <- SyliAtlas.Market.for_country(ctx.code) do
      e = x["exchange"]

      answer =
        cond do
          x["regional"] and (e["listed"] || 0) > 0 ->
            gettext(
              "Its companies are listed on the %{exchange}, the regional exchange shared by %{count} countries (%{listed} listed securities).",
              exchange: e["name"],
              count: length(e["countries"] || []),
              listed: e["listed"]
            )

          x["regional"] ->
            gettext(
              "Its companies are listed on the %{exchange}, the regional exchange shared by %{count} countries.",
              exchange: e["name"],
              count: length(e["countries"] || [])
            )

          true ->
            gettext("Yes: the %{exchange}, with %{listed} listed securities.",
              exchange: e["name"],
              listed: e["listed"]
            )
        end

      q(
        "exchange",
        gettext("Does %{name} have a stock exchange?", names(ctx.name, [])),
        answer,
        Paths.exchange(ctx.locale, e["code"])
      )
    else
      _ -> nil
    end
  end

  defp electricity(ctx) do
    with %{"latest" => %{"electricity" => %{"value" => v, "year" => y}}} <-
           SyliAtlas.WorldBank.for_country(ctx.code) do
      q(
        "electricity",
        gettext("What share of the population of %{name} has electricity?", names(ctx.name, [])),
        gettext("%{value} of the population in %{year} (World Bank).",
          value: number(v, 1, ctx.locale) <> " %",
          year: y
        ),
        tab(ctx, :society)
      )
    end
  end
end
