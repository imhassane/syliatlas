defmodule SyliAtlasWeb.CommunityController do
  @moduledoc """
  Regional economic communities and monetary unions: totals computed from
  the IMF series of their members, by the same rules as the regions.
  """
  use SyliAtlasWeb, :controller

  alias SyliAtlas.Economy.{Communities, Convergence}
  alias SyliAtlas.Profiles.Builder
  alias SyliAtlas.Sources.Indicators
  alias SyliAtlasWeb.{NotFoundError, Paths, PublicData, Seo}

  plug :put_layout, false

  @year 2025

  def index(conn, _params) do
    locale = conn.assigns.locale
    paths = %{"fr" => Paths.communities("fr"), "en" => Paths.communities("en")}
    rows = Enum.map(Communities.all(), &summary(&1, locale))
    answer = answer(rows, locale)

    render(conn, :index,
      page_title: gettext("Economic communities of Africa: GDP, growth, debt"),
      seo:
        Seo.page(locale, paths, answer, %{
          json_ld: [
            Seo.breadcrumbs([
              {"Syli Atlas", Paths.home(locale)},
              {gettext("Economic communities"), paths[locale]}
            ])
          ]
        }),
      alternates: Seo.alternates_for_header(paths),
      rows: Enum.sort_by(rows, &(-(&1.gdp || 0))),
      year: @year,
      answer: answer,
      edition: edition(rows)
    )
  end

  def show(conn, %{"slug" => slug}) do
    locale = conn.assigns.locale

    community =
      Communities.by_slug(slug, locale) || Communities.by_slug(slug, other(locale)) ||
        raise NotFoundError

    paths = %{
      "fr" => Paths.community("fr", community.slug["fr"]),
      "en" => Paths.community("en", community.slug["en"])
    }

    if conn.request_path != paths[locale] do
      redirect(conn, to: paths[locale])
    else
      s = summary(community, locale)
      name = community.short[locale]

      members =
        s.members
        |> Enum.map(fn m ->
          %{
            code: m["code"],
            name: m["name"][locale],
            slug: m["slug"][locale],
            gdp: at(m["series"], "gdp_usd_bn"),
            growth: at(m["series"], "real_gdp_growth"),
            debt: at(m["series"], "public_debt_pct_gdp"),
            balance: at(m["series"], "fiscal_balance_pct_gdp"),
            convergence:
              community[:zone] &&
                Convergence.check(m["code"], m["series"], @year, Indicators.first_year())
          }
        end)
        |> Enum.sort_by(&(-(&1.gdp || 0)))

      answer = community_answer(community, s, locale)

      render(conn, :show,
        page_title: "#{name} · " <> community.name[locale],
        seo:
          Seo.page(locale, paths, answer, %{
            json_ld: [
              Seo.breadcrumbs([
                {"Syli Atlas", Paths.home(locale)},
                {gettext("Economic communities"), Paths.communities(locale)},
                {name, paths[locale]}
              ])
            ]
          }),
        alternates: Seo.alternates_for_header(paths),
        community: community,
        name: name,
        summary: s,
        members: members,
        others: Enum.reject(Communities.all(), &(&1.code == community.code)),
        year: @year,
        answer: answer,
        edition: edition([s])
      )
    end
  end

  # Totals change only with the IMF data: computed once per data version,
  # kept in memory (the six communities together take ~10 ms to add up).
  defp summary(community, _locale) do
    key = {__MODULE__, :summary, community.code}
    version = SyliAtlas.Profiles.data_version()

    case :persistent_term.get(key, nil) do
      {^version, s} ->
        s

      _ ->
        s = compute_summary(community)
        :persistent_term.put(key, {version, s})
        s
    end
  end

  defp compute_summary(community) do
    members = PublicData.series_for(community.members)
    series = Builder.aggregate_series(Enum.map(members, & &1["series"]))

    %{
      community: community,
      members: members,
      series: series,
      gdp: at(series, "gdp_usd_bn"),
      population: at(series, "population_m"),
      growth: at(series, "real_gdp_growth"),
      debt: at(series, "public_debt_pct_gdp"),
      balance: at(series, "fiscal_balance_pct_gdp")
    }
  end

  defp edition(_rows) do
    case SyliAtlas.Sources.published_edition("imf_weo") do
      nil -> nil
      e -> e.label
    end
  end

  defp at(series, key), do: PublicData.at(series[key], @year)

  defp answer(rows, locale) do
    largest = Enum.max_by(rows, &(&1.gdp || 0), fn -> nil end)
    fastest = Enum.max_by(rows, &(&1.growth || -99), fn -> nil end)

    gettext(
      "In %{year}, %{largest} is the largest African economic community by GDP (%{gdp}), and %{fastest} the fastest-growing (%{growth}), according to IMF figures added up by Syli Atlas.",
      year: @year,
      largest: largest && largest.community.short[locale],
      gdp: largest && SyliAtlasWeb.Format.value(largest.gdp, "gdp_usd_bn", locale),
      fastest: fastest && fastest.community.short[locale],
      growth: fastest && SyliAtlasWeb.Format.value(fastest.growth, "real_gdp_growth", locale)
    )
  end

  defp community_answer(c, s, locale) do
    gettext(
      "%{name} (%{n} members): GDP of %{gdp} in %{year}, %{population} inhabitants, growth of %{growth} and public debt of %{debt} of GDP (IMF, Syli Atlas totals).",
      name: c.short[locale],
      n: length(c.members),
      gdp: SyliAtlasWeb.Format.value(s.gdp, "gdp_usd_bn", locale),
      year: @year,
      population: SyliAtlasWeb.Format.value(s.population, "population_m", locale),
      growth: SyliAtlasWeb.Format.value(s.growth, "real_gdp_growth", locale),
      debt: SyliAtlasWeb.Format.value(s.debt, "public_debt_pct_gdp", locale)
    )
  end

  defp other("fr"), do: "en"
  defp other(_), do: "fr"
end
