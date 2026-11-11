defmodule SyliAtlasWeb.OgImage.Specs do
  @moduledoc """
  What the share image of a page shows, from the page's address: the router
  says which page it is, and the spec reads the same precomputed documents
  as the page (IMF profiles, ratings, communities, market snapshots).
  An address that is not a public page gives nil (404).
  """
  use Gettext, backend: SyliAtlasWeb.Gettext

  import SyliAtlasWeb.Format, only: [value: 3, change: 3, number: 3, names: 1]

  alias SyliAtlas.Geo
  alias SyliAtlas.Geo.Area
  alias SyliAtlasWeb.{OgImage, Paths, PublicData, Seo}

  @doc "The spec of the page at `path` (« /fr/pays/senegal »), or nil."
  def for_path(path) do
    with [locale | _] when locale in ["fr", "en"] <- String.split(path, "/", trim: true),
         %{plug: plug, plug_opts: action, path_params: params} <-
           Phoenix.Router.route_info(SyliAtlasWeb.Router, "GET", path, "localhost") do
      Gettext.put_locale(SyliAtlasWeb.Gettext, locale)

      spec =
        try do
          spec(plug, action, params, locale)
        rescue
          _ -> nil
        end

      spec && Map.merge(%{url: Seo.url(path), locale: locale}, spec)
    else
      _ -> nil
    end
  end

  # ---------------------------------------------------------------------------

  defp spec(SyliAtlasWeb.AreaController, :show, %{"slug" => slug} = params, locale) do
    area = Geo.get_area_by_slug(slug, locale)
    tab = (params["tab"] && Paths.tab_from_segment(params["tab"])) || :overview
    {from, to} = SyliAtlas.Profiles.Builder.default_period()
    data = area && PublicData.area(area.code, from, to)
    data && area_spec(area, tab, data, from, to, locale)
  end

  defp spec(SyliAtlasWeb.RatingsController, :show, %{"slug" => slug}, locale) do
    doc = SyliAtlas.Ratings.document()
    entry = doc && Enum.find(Map.values(doc["countries"]), &(&1["slug"][locale] == slug))
    entry && rating_spec(entry, doc, locale)
  end

  defp spec(SyliAtlasWeb.RankingController, :index, _params, locale) do
    {_from, to} = SyliAtlas.Profiles.Builder.default_period()
    ranking_spec("gdp_usd_bn", to, locale)
  end

  defp spec(SyliAtlasWeb.RankingController, :topic, %{"topic" => slug}, locale) do
    {_from, to} = SyliAtlas.Profiles.Builder.default_period()

    case SyliAtlasWeb.Topics.ranking_indicator(slug) do
      nil ->
        nil

      indicator ->
        indicator
        |> ranking_spec(to, locale)
        |> Map.merge(%{
          title: SyliAtlasWeb.Topics.ranking_title(indicator, to),
          source: gettext("Source: IMF")
        })
    end
  end

  defp spec(SyliAtlasWeb.QuestionsController, :show, %{"slug" => slug}, locale) do
    with id when is_binary(id) <- SyliAtlasWeb.Topics.question(slug),
         %{} = a <- SyliAtlasWeb.QuestionsController.answer(id, locale) do
      text_spec(SyliAtlasWeb.Topics.question_text(id), a.text, %{
        eyebrow: gettext("Question"),
        source: a.source
      })
    end
  end

  defp spec(SyliAtlasWeb.CommunityController, :show, %{"slug" => slug}, locale) do
    community = Enum.find(SyliAtlas.Economy.Communities.all(), &(&1.slug[locale] == slug))
    community && community_spec(community, locale)
  end

  defp spec(SyliAtlasWeb.CompareController, :show, %{"slugs" => slugs}, locale)
       when length(slugs) == 2 do
    areas = Enum.map(slugs, &Geo.get_area_by_slug(&1, locale))
    if Enum.all?(areas), do: pair_spec(areas, locale)
  end

  defp spec(
         SyliAtlasWeb.MarketController,
         :security,
         %{"exchange" => code, "ticker" => t},
         locale
       ) do
    with true <- SyliAtlas.Market.public?(),
         {doc, row} <- SyliAtlas.Market.security(code, String.downcase(t)) do
      security_spec(doc, row, locale)
    else
      _ -> nil
    end
  end

  defp spec(SyliAtlasWeb.MarketController, :exchange, %{"exchange" => code}, locale) do
    with true <- SyliAtlas.Market.public?(), %{} = doc <- SyliAtlas.Market.exchange(code) do
      exchange_spec(doc, locale)
    else
      _ -> nil
    end
  end

  defp spec(SyliAtlasWeb.PageController, :home, _params, locale) do
    {from, to} = SyliAtlas.Profiles.Builder.default_period()

    case PublicData.area("africa", from, to) do
      nil ->
        text_spec(gettext("African economies in verifiable figures"), nil)

      data ->
        Map.put(
          area_spec(Geo.get_area_by_code("africa"), :overview, data, from, to, locale),
          :eyebrow,
          "syliatlas.com"
        )
    end
  end

  defp spec(SyliAtlasWeb.DebtController, :index, _params, locale) do
    {_from, to} = SyliAtlas.Profiles.Builder.default_period()

    "public_debt_pct_gdp"
    |> ranking_spec(to, locale)
    |> Map.merge(%{
      eyebrow: gettext("Debt"),
      title: gettext("The most indebted African countries in %{year}", year: to),
      source: gettext("Source: IMF · gross public debt, % of GDP")
    })
  end

  defp spec(SyliAtlasWeb.RatingsController, :index, _params, locale) do
    case SyliAtlas.Ratings.document() do
      nil ->
        nil

      doc ->
        text_spec(
          gettext("Sovereign ratings of the 54 African countries (S&P, Moody's, Fitch)"),
          SyliAtlasWeb.RatingsController.answer(doc, locale),
          %{
            eyebrow: gettext("Sovereign ratings"),
            source: gettext("Agencies: S&P, Moody's, Fitch")
          }
        )
    end
  end

  defp spec(SyliAtlasWeb.CommunityController, :index, _params, _locale) do
    text_spec(
      gettext("Economic communities of Africa: GDP, growth, debt"),
      gettext("ECOWAS, AES, WAEMU, CEMAC, EAC, SADC: members and totals from IMF figures."),
      %{eyebrow: gettext("Economic communities"), source: gettext("IMF · Syli Atlas totals")}
    )
  end

  defp spec(SyliAtlasWeb.RegionsController, :index, _params, _locale) do
    text_spec(
      gettext("Regions of Africa compared: GDP, growth, inflation and debt"),
      gettext(
        "North, West, Central, East and Southern Africa side by side: growth, income, inflation and debt, from IMF data."
      ),
      %{eyebrow: gettext("Regions"), source: gettext("Source: IMF")}
    )
  end

  defp spec(SyliAtlasWeb.MarketController, action, _params, _locale)
       when action in [:index, :etfs] do
    if SyliAtlas.Market.public?() do
      text_spec(
        if(action == :etfs,
          do: gettext("Funds exposed to Africa (ETF): prices and daily change"),
          else: gettext("African stock exchanges: indices, prices and latest session")
        ),
        gettext(
          "Every African stock exchange followed by Syli Atlas: main index, daily change, number of listed securities, with the source and date of each figure."
        ),
        %{
          eyebrow: gettext("Stock exchanges"),
          source: "Data by MansaAPI · " <> gettext("close, not live")
        }
      )
    end
  end

  defp spec(SyliAtlasWeb.PageController, :method, _params, _locale) do
    text_spec(
      gettext("Sources and method: IMF, World Bank, CEPII, rating agencies"),
      gettext("Where Syli Atlas figures come from and how totals and changes are computed.")
    )
  end

  # Any other public page (accessibility, a comparison of more than two
  # areas…): the site itself.
  defp spec(_plug, _action, _params, _locale) do
    text_spec(
      gettext("Economic data of the 54 African countries: GDP, debt, inflation"),
      gettext("African economies in verifiable figures: every figure names its public source.")
    )
  end

  # ---------------------------------------------------------------------------
  # Profiles

  defp area_spec(area, tab, data, from, to, locale) do
    s = data["profile"]["series"]
    name = Area.name(area, locale)
    at = fn k -> PublicData.at(s[k], to) end
    region = area.region_code && Geo.get_area_by_code(area.region_code)

    eyebrow =
      cond do
        area.kind == "country" ->
          communities = SyliAtlas.Economy.Communities.for_country(area.code)

          [
            region && Area.name(region, locale)
            | Enum.map(Enum.take(communities, 1), & &1.short[locale])
          ]
          |> Enum.reject(&is_nil/1)
          |> Enum.join(" · ")

        true ->
          gettext("Region")
      end

    base = %{
      layout: :figure,
      title: name,
      eyebrow: eyebrow,
      source: gettext("Source: IMF, %{label}", label: short_edition(data, locale))
    }

    case tab do
      :finances ->
        Map.merge(base, %{
          figure: value(at.("public_debt_pct_gdp"), "public_debt_pct_gdp", locale),
          caption: gettext("public debt, % of GDP, in %{year}", year: to),
          pills: [
            {gettext("Fiscal balance %{v}",
               v: value(at.("fiscal_balance_pct_gdp"), "fiscal_balance_pct_gdp", locale)
             ), false}
          ],
          series: slice(s["public_debt_pct_gdp"], 2015, to),
          series_label: gettext("Public debt, % of GDP"),
          from_label: "2015",
          to_label: to_string(to)
        })

      :economy ->
        Map.merge(base, %{
          figure: value(at.("gdp_usd_bn"), "gdp_usd_bn", locale),
          caption: gettext("GDP in %{year}, current dollars", year: to),
          pills: [
            {gettext("%{v} per person",
               v: value(at.("gdp_per_capita_usd"), "gdp_per_capita_usd", locale)
             ), false}
          ],
          series: slice(s["gdp_usd_bn"], 2015, to),
          series_label: gettext("GDP, current dollars"),
          from_label: "2015",
          to_label: to_string(to)
        })

      _ ->
        rank = area.kind == "country" && gdp_rank(area.code, to)

        Map.merge(base, %{
          figure: rate(at.("real_gdp_growth"), locale),
          caption: gettext("real GDP growth in %{year}", year: to),
          pills:
            [
              {gettext("GDP %{v}", v: value(at.("gdp_usd_bn"), "gdp_usd_bn", locale)), false},
              rank && {gettext("no. %{rank} in Africa", rank: rank), true}
            ]
            |> Enum.filter(& &1),
          series: rebase(slice(s["real_gdp_index"], 2015, to), from),
          series_label: gettext("Real GDP · index 100 in %{year}", year: from),
          from_label: "2015",
          to_label: to_string(to),
          note: nil
        })
    end
    |> Map.put(:alt_tab, tab)
  end

  defp short_edition(data, locale) do
    label = get_in(data, ["profile", "edition", "label"]) || ""

    case Regex.run(~r/\((\w+) (\d{4})\)/, label) do
      [_, month, year] ->
        m = String.slice(month, 0, 3)
        if locale == "fr", do: "#{fr_month(m)} #{year}", else: "#{m} #{year}"

      _ ->
        label
    end
  end

  @fr_months %{
    "Jan" => "janv.",
    "Feb" => "févr.",
    "Mar" => "mars",
    "Apr" => "avr.",
    "May" => "mai",
    "Jun" => "juin",
    "Jul" => "juil.",
    "Aug" => "août",
    "Sep" => "sept.",
    "Oct" => "oct.",
    "Nov" => "nov.",
    "Dec" => "déc."
  }
  defp fr_month(m), do: @fr_months[m] || m

  defp slice(values, first, last) when is_list(values),
    do: Enum.slice(values, (first - 2015)..(last - 2015)//1)

  defp slice(_, _, _), do: []

  defp rebase(values, from) do
    base = Enum.at(values, from - 2015)
    if is_number(base) and base != 0, do: Enum.map(values, &(&1 && &1 / base * 100)), else: values
  end

  defp rate(nil, locale), do: number(nil, 1, locale)
  defp rate(v, locale), do: number(v, 1, locale) <> " %"

  defp gdp_rank(code, to) do
    rows =
      PublicData.ranking("gdp_usd_bn", to - 1, to, mode: "value")
      |> Enum.filter(&is_number(&1["value"]))

    case Enum.find_index(rows, &(&1["code"] == code)) do
      nil -> nil
      i -> i + 1
    end
  end

  # ---------------------------------------------------------------------------
  # Ratings

  defp rating_spec(entry, doc, locale) do
    name = entry["name"][locale]
    alias SyliAtlasWeb.RatingComponents, as: R

    lines =
      for a <- entry["agencies"] || [] do
        date = R.date_text(a["action_date"], locale)

        "#{R.agency_name(a["agency"])} #{SyliAtlas.Ratings.Scale.display(a["rating"])}" <>
          if(date, do: " · #{date}", else: "")
      end

    %{
      layout: :rating,
      eyebrow: gettext("Sovereign rating"),
      title: gettext("Credit rating of %{name}", names(name)),
      figure: entry["label"] || "—",
      lines: if(lines == [], do: [gettext("Not rated by S&P, Moody's or Fitch")], else: lines),
      score: entry["average"] && round(entry["average"]),
      labels: %{default: gettext("Default"), investment: gettext("BBB− · investment grade")},
      note:
        entry["rank"] &&
          gettext("No. %{rank} of the %{of} African countries rated",
            rank: entry["rank"],
            of: doc["rated"]
          ),
      source:
        gettext("Agencies: S&P, Moody's, Fitch · as of %{date}",
          date: R.date_text(doc["as_of"], locale)
        )
    }
  end

  # ---------------------------------------------------------------------------
  # Ranking, communities, comparisons

  defp ranking_spec(indicator, to, locale) do
    rows =
      PublicData.ranking(indicator, to - 1, to, mode: "value", locale: locale)
      |> Enum.filter(&is_number(&1["value"]))
      |> Enum.take(5)
      |> Enum.map(&{&1["name"], &1["value"], value(&1["value"], indicator, locale)})

    %{
      layout: :bars,
      eyebrow: gettext("Ranking"),
      title: gettext("The largest economies of Africa in %{year}", year: to),
      rows: rows,
      source: gettext("Source: IMF · current dollars")
    }
  end

  defp community_spec(community, locale) do
    s = SyliAtlasWeb.CommunityController.summary_for(community)
    year = 2025

    %{
      layout: :totals,
      eyebrow: gettext("Economic community"),
      title: community.short[locale],
      subtitle:
        gettext("%{name} · %{count} members",
          name: community.name[locale],
          count: length(s.members)
        ),
      figure_label: gettext("GDP %{year}", year: year),
      figure: value(s.gdp, "gdp_usd_bn", locale),
      figure_note:
        s.population &&
          gettext("%{v} inhabitants", v: value(s.population, "population_m", locale)),
      facts: [
        {gettext("Growth %{year}", year: year), rate(s.growth, locale)},
        {gettext("Public debt"), value(s.debt, "public_debt_pct_gdp", locale)}
      ],
      source: gettext("IMF · Syli Atlas totals")
    }
  end

  defp pair_spec([a, b], locale) do
    {from, to} = SyliAtlas.Profiles.Builder.default_period()
    items = PublicData.compare([a.code, b.code], from, to)
    by = Map.new(items, &{&1["code"], &1})

    line = fn area ->
      item = by[area.code]
      series = item && rebase(slice(item["series"]["real_gdp_index"], from, to), from)
      ch = item && item["real_gdp_change_pct"]

      {Area.name(area, locale), change(ch, "real_gdp_index", locale), series || []}
    end

    %{
      layout: :pair,
      eyebrow: gettext("Comparison"),
      title: gettext("%{a} or %{b}?", a: Area.name(a, locale), b: Area.name(b, locale)),
      lines: [line.(a), line.(b)],
      from_label: to_string(from),
      to_label: to_string(to),
      source: gettext("Source: IMF · real GDP %{from} → %{to}", from: from, to: to)
    }
  end

  # ---------------------------------------------------------------------------
  # Markets: the source's figures with its credit (MansaAPI licence).

  defp security_spec(doc, row, locale) do
    alias SyliAtlasWeb.MarketComponents, as: M
    e = doc["exchange"]
    i = doc["index"] || %{}
    change = M.to_f(row["change_pct"])

    country =
      Enum.find_value(e["country_names"] || [], fn c ->
        c["code"] == row["country"] && (c["name"][locale] || c["name"])
      end)

    %{
      layout: :quote,
      eyebrow: "#{e["short_name"]} · " <> gettext("end of day"),
      title: "#{row["name"]} #{row["ticker"]}",
      subtitle:
        [gettext("Listed on the %{exchange}", exchange: e["short_name"]), country]
        |> Enum.filter(&is_binary/1)
        |> Enum.join(" · "),
      figure: row["close"] && "#{M.price(row["close"], locale)} #{row["currency"]}",
      change:
        row["change_pct"] && M.pct(row["change_pct"], locale) |> String.replace(~r/^[▲▼]\s*/u, ""),
      direction: direction(change),
      note:
        row["trade_date"] && gettext("close of %{date}", date: M.day(row["trade_date"], locale)),
      facts:
        [
          row["volume"] && {gettext("Volume"), M.integer(row["volume"], locale)},
          row["value"] &&
            {gettext("Value traded"), M.amount(row["value"], row["currency"], locale)},
          i["value"] && {e["index_name"] || e["short_name"], M.price(i["value"], locale)}
        ]
        |> Enum.filter(& &1),
      source: "Data by MansaAPI · " <> gettext("close, not live")
    }
  end

  defp exchange_spec(doc, locale) do
    alias SyliAtlasWeb.MarketComponents, as: M
    e = doc["exchange"]
    i = doc["index"] || %{}
    change = M.to_f(i["change_pct"])

    %{
      layout: :quote,
      eyebrow: gettext("Stock exchange") <> " · " <> gettext("end of day"),
      title: e["short_name"],
      subtitle: OgImage.fit(e["name"] || "", 64),
      figure: (i["value"] && M.price(i["value"], locale)) || to_string(e["listed"] || ""),
      change:
        i["change_pct"] && M.pct(i["change_pct"], locale) |> String.replace(~r/^[▲▼]\s*/u, ""),
      direction: direction(change),
      note:
        if(i["value"],
          do: (e["index_name"] || "") <> " · " <> (M.day(i["date"], locale) || ""),
          else: gettext("listed securities")
        ),
      facts:
        [
          {gettext("Listed securities"),
           to_string(e["listed"] || length(doc["securities"] || []))},
          i["ytd_pct"] && {gettext("Since 1 January"), M.ytd(i["ytd_pct"], locale)}
        ]
        |> Enum.filter(& &1),
      source: "Data by MansaAPI · " <> gettext("close, not live")
    }
  end

  defp direction(n) when is_number(n) and n > 0, do: :up
  defp direction(n) when is_number(n) and n < 0, do: :down
  defp direction(_), do: nil

  @doc "A title and a sentence, for pages without a figure of their own."
  def text_spec(title, text, extra \\ %{}) do
    Map.merge(%{layout: :text, title: title, text: text, eyebrow: "syliatlas.com"}, extra)
  end
end
