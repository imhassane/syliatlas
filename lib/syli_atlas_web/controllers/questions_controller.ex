defmodule SyliAtlasWeb.QuestionsController do
  @moduledoc """
  One page per question people ask about African economies
  (`SyliAtlasWeb.Topics`): the answer in a sentence, written from the data of
  the day, then the table behind it and the page that goes further.
  """
  use SyliAtlasWeb, :controller

  alias SyliAtlas.Geo
  alias SyliAtlas.Geo.Area
  alias SyliAtlasWeb.{NotFoundError, Paths, PublicData, Seo, Topics}
  import SyliAtlasWeb.Format, only: [names: 2]

  plug :put_layout, false

  def index(conn, _params) do
    locale = conn.assigns.locale
    paths = SyliAtlas.Locales.each(fn l -> Topics.questions_path(l) end)
    title = gettext("Questions on African economies, answered with the figures")

    render(conn, :index,
      page_title: title,
      heading: title,
      seo:
        Seo.page(
          locale,
          paths,
          gettext(
            "The richest, fastest-growing, most indebted African countries, the GDP of Africa, credit ratings: each question answered from IMF, World Bank and rating agency figures."
          ),
          %{
            json_ld: [
              Seo.breadcrumbs([
                {"Syli Atlas", Paths.home(locale)},
                {gettext("Questions"), paths[locale]}
              ]),
              Seo.item_list(
                title,
                for(
                  q <- Topics.questions(),
                  do: {Topics.question_text(q), Topics.question_path(locale, q)}
                )
              )
            ]
          }
        ),
      alternates: Seo.alternates_for_header(paths),
      questions:
        for(
          q <- Topics.questions(),
          do: {Topics.question_text(q), Topics.question_path(locale, q)}
        )
    )
  end

  def show(conn, %{"slug" => slug}) do
    locale = conn.assigns.locale
    id = Topics.question(slug) || raise NotFoundError
    paths = SyliAtlas.Locales.each(fn l -> Topics.question_path(l, id) end)

    if conn.request_path != paths[locale] do
      conn |> put_status(301) |> redirect(to: paths[locale])
    else
      a = answer(id, locale) || raise NotFoundError
      question = Topics.question_text(id)

      render(conn, :show,
        page_title: question,
        heading: question,
        seo:
          Seo.page(locale, paths, a.text, %{
            json_ld: [
              Seo.breadcrumbs([
                {"Syli Atlas", Paths.home(locale)},
                {gettext("Questions"), Topics.questions_path(locale)},
                {question, paths[locale]}
              ]),
              Seo.faq([{question, a.text}]),
              Seo.item_list(a.table_title, for(r <- a.rows, do: {r.name, r.path}))
            ]
          }),
        alternates: Seo.alternates_for_header(paths),
        id: id,
        answer: a,
        others:
          for(
            q <- Topics.questions(),
            q != id,
            do: {Topics.question_text(q), Topics.question_path(locale, q)}
          )
      )
    end
  end

  # ---------------------------------------------------------------------------
  # Answers: %{text, rows: [%{name, path, value}], table_title, value_label,
  # more: {label, path}, source}

  @doc false
  def answer(id, locale) do
    {_from, to} = SyliAtlas.Profiles.Builder.default_period()
    build(id, to, locale)
  end

  defp build("richest", year, locale) do
    gdp = top("gdp_usd_bn", year, locale)
    per = top("gdp_per_capita_usd", year, locale)

    with [first | _] <- gdp, [richest | _] <- per do
      %{
        text:
          gettext(
            "By GDP, %{name} is the largest economy in Africa in %{year} (%{value}, IMF). Per person, the richest country is %{per_name} (%{per_value} of GDP per capita).",
            names(first.name,
              year: year,
              value: first.value,
              per_name: SyliAtlas.Geo.French.bindings(richest.name, locale)[:the_name],
              per_value: richest.value
            )
          ),
        rows: Enum.take(gdp, 10),
        table_title: gettext("Largest economies in Africa, GDP %{year}", year: year),
        value_label: gettext("GDP, current dollars"),
        more:
          {gettext("All countries by GDP per capita"),
           Topics.ranking_path(locale, "gdp_per_capita_usd")},
        source: imf_source()
      }
    end
  end

  defp build("largest", year, locale),
    do:
      ranking_answer(
        "gdp_usd_bn",
        year,
        locale,
        &gettext(
          "The five largest economies in Africa in %{year}: %{list} (GDP in current dollars, IMF).",
          year: year,
          list: &1
        )
      )

  defp build("per_capita", year, locale),
    do:
      ranking_answer(
        "gdp_per_capita_usd",
        year,
        locale,
        &gettext(
          "Richest African countries per person in %{year}: %{list} (GDP per capita in current dollars, IMF).",
          year: year,
          list: &1
        )
      )

  defp build("fastest", year, locale),
    do:
      ranking_answer(
        "real_gdp_growth",
        year,
        locale,
        &gettext("Fastest-growing African economies in %{year}: %{list} (real GDP growth, IMF).",
          year: year,
          list: &1
        )
      )

  defp build("indebted", year, locale),
    do:
      ranking_answer(
        "public_debt_pct_gdp",
        year,
        locale,
        &gettext(
          "Most indebted African countries in %{year}: %{list} (gross public debt in % of GDP, IMF).",
          year: year,
          list: &1
        )
      )

  defp build("inflation", year, locale),
    do:
      ranking_answer(
        "inflation",
        year,
        locale,
        &gettext(
          "Highest inflation in Africa in %{year}: %{list} (average annual change in prices, IMF).",
          year: year,
          list: &1
        )
      )

  defp build("populous", year, locale),
    do:
      ranking_answer(
        "population_m",
        year,
        locale,
        &gettext("Most populous African countries in %{year}: %{list} (IMF).",
          year: year,
          list: &1
        )
      )

  defp build("africa_gdp", year, locale) do
    with %{} = africa <- PublicData.area("africa", year - 1, year),
         %{} = world <- PublicData.area("WLD", year - 1, year) do
      s = africa["profile"]["series"]
      gdp = PublicData.at(s["gdp_usd_bn"], year)
      world_gdp = PublicData.at(world["profile"]["series"]["gdp_usd_bn"], year)
      share = gdp && world_gdp && gdp / world_gdp * 100

      %{
        text:
          gettext(
            "The GDP of Africa reached %{gdp} in %{year} (IMF), %{share} of world GDP. Real growth: %{growth}.",
            gdp: SyliAtlasWeb.Format.value(gdp, "gdp_usd_bn", locale),
            year: year,
            share: SyliAtlasWeb.Format.number(share, 1, locale) <> " %",
            growth:
              SyliAtlasWeb.Format.value(
                PublicData.at(s["real_gdp_growth"], year),
                "real_gdp_growth",
                locale
              )
          ),
        rows: Enum.take(top("gdp_usd_bn", year, locale), 10),
        table_title: gettext("Largest economies in Africa, GDP %{year}", year: year),
        value_label: gettext("GDP, current dollars"),
        more:
          {gettext("The economy of Africa"), Paths.area(locale, Geo.get_area_by_code("africa"))},
        source: imf_source()
      }
    end
  end

  defp build("fastest_region", year, locale) do
    rows =
      Geo.list_regions()
      |> Enum.map(fn r ->
        d = PublicData.area(r.code, year - 1, year)
        v = d && PublicData.at(d["profile"]["series"]["real_gdp_growth"], year)
        %{name: Area.name(r, locale), path: Paths.area(locale, r), raw: v}
      end)
      |> Enum.filter(&is_number(&1.raw))
      |> Enum.sort_by(&(-&1.raw))
      |> Enum.map(
        &Map.put(&1, :value, SyliAtlasWeb.Format.value(&1.raw, "real_gdp_growth", locale))
      )

    with [first | _] <- rows do
      %{
        text:
          gettext(
            "In %{year}, %{name} is the fastest-growing region of Africa (%{value} real growth, IMF).",
            names(first.name, year: year, value: first.value)
          ),
        rows: rows,
        table_title: gettext("Real GDP growth by region, %{year}", year: year),
        value_label: gettext("Real GDP growth"),
        more: {gettext("The regions of Africa compared"), Paths.regions(locale)},
        source: gettext("Source: IMF · regional totals by Syli Atlas, weighted by GDP in PPP")
      }
    end
  end

  defp build("investment_grade", _year, locale) do
    with %{} = doc <- SyliAtlas.Ratings.document() do
      rows = rating_rows(doc, locale, &(&1["band"] == "investment"))

      %{
        text:
          gettext(
            "%{count} African countries are investment grade on average of S&P, Moody's and Fitch: %{list}. %{rated} of the 54 countries are rated.",
            count: length(rows),
            list: Enum.map_join(rows, ", ", &"#{&1.name} (#{&1.value})"),
            rated: doc["rated"]
          ),
        rows: rating_rows(doc, locale, fn _ -> true end) |> Enum.take(10),
        table_title: gettext("Best sovereign ratings in Africa"),
        value_label: gettext("Rating"),
        more: {gettext("All sovereign ratings"), Paths.ratings(locale)},
        source: gettext("Agencies: S&P, Moody's, Fitch")
      }
    end
  end

  defp build("best_rating", _year, locale) do
    with %{} = doc <- SyliAtlas.Ratings.document(),
         [best | _] = rows <- rating_rows(doc, locale, fn _ -> true end) do
      entry = doc["countries"][best.code]

      %{
        text:
          gettext(
            "%{name} has the best credit rating in Africa: %{agencies} (average %{rating}).",
            name: SyliAtlas.Geo.French.bindings(best.name, locale)[:The_name],
            agencies: SyliAtlasWeb.RatingComponents.agencies_text(entry),
            rating: best.value
          ),
        rows: Enum.take(rows, 10),
        table_title: gettext("Best sovereign ratings in Africa"),
        value_label: gettext("Rating"),
        more: {gettext("All sovereign ratings"), Paths.ratings(locale)},
        source: gettext("Agencies: S&P, Moody's, Fitch")
      }
    end
  end

  defp build("largest_community", year, locale) do
    rows =
      SyliAtlasWeb.CommunityController.summaries()
      |> Enum.filter(&is_number(&1.gdp))
      |> Enum.sort_by(&(-&1.gdp))
      |> Enum.map(fn s ->
        %{
          name: SyliAtlas.Locales.pick(s.community.short, locale),
          path: Paths.community(locale, SyliAtlas.Locales.pick(s.community.slug, locale)),
          value: SyliAtlasWeb.Format.value(s.gdp, "gdp_usd_bn", locale),
          full: SyliAtlas.Locales.pick(s.community.name, locale)
        }
      end)

    with [first | _] <- rows do
      %{
        text:
          gettext(
            "By GDP, %{name} (%{full}) is the largest economic community in Africa in %{year}: %{value} (IMF figures added up by Syli Atlas).",
            name: first.name,
            full: first.full,
            year: year,
            value: first.value
          ),
        rows: rows,
        table_title: gettext("Economic communities of Africa by GDP, %{year}", year: year),
        value_label: gettext("GDP, current dollars"),
        more: {gettext("Economic communities"), Paths.communities(locale)},
        source: gettext("IMF · Syli Atlas totals")
      }
    end
  end

  defp build(_id, _year, _locale), do: nil

  defp ranking_answer(indicator, year, locale, sentence) do
    case top(indicator, year, locale) do
      [] ->
        nil

      rows ->
        %{
          text:
            sentence.(rows |> Enum.take(5) |> Enum.map_join(", ", &"#{&1.name} (#{&1.value})")),
          rows: Enum.take(rows, 10),
          table_title: Topics.ranking_title(indicator, year),
          value_label: SyliAtlasWeb.PageComponents.indicator_label(indicator),
          more:
            {gettext("The full ranking of the 54 countries"),
             Topics.ranking_path(locale, indicator)},
          source: imf_source()
        }
    end
  end

  defp top(indicator, year, locale) do
    PublicData.ranking(indicator, year - 1, year, mode: "value", locale: locale)
    |> Enum.filter(&is_number(&1["value"]))
    |> Enum.map(fn r ->
      %{
        name: r["name"],
        path: Paths.area(locale, "country", r["slug"]),
        value: SyliAtlasWeb.Format.value(r["value"], indicator, locale)
      }
    end)
  end

  defp rating_rows(doc, locale, keep?) do
    for code <- doc["ranking"], e = doc["countries"][code], keep?.(e) do
      %{
        code: code,
        name: SyliAtlas.Locales.pick(e["name"], locale),
        path: Paths.rating(locale, SyliAtlas.Locales.pick(e["slug"], locale)),
        value: e["label"]
      }
    end
  end

  defp imf_source do
    case SyliAtlas.Sources.published_edition("imf_weo") do
      nil -> gettext("Source: IMF")
      e -> gettext("Source: IMF, %{label}", label: e.label)
    end
  end
end
