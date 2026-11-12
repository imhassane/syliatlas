defmodule SyliAtlas.Accounts.AlertEmails do
  @moduledoc """
  The alert emails and the digest, after the « E-mails · alertes » boards
  of the canvas, in the member's language. Every one carries links to
  manage the alerts and to stop them, and the one-click unsubscribe
  headers (RFC 8058) that mail clients show.
  """

  use Gettext, backend: SyliAtlasWeb.Gettext

  alias SyliAtlas.Accounts.{AlertDelivery, Emails, Unsubscribe, User}
  alias SyliAtlas.Geo
  alias SyliAtlasWeb.Paths

  @doc "The email of one immediate delivery."
  def alert(%User{} = user, %AlertDelivery{kind: kind, payload: p} = delivery) do
    in_locale(user.locale, fn ->
      country = country(p["country_code"], user.locale)
      content = content(kind, p, country, user.locale)
      token = Unsubscribe.token(:alert, delivery.alert_id)

      Emails.compose(user.email, user.locale,
        subject: content.subject,
        preheader: content.preheader,
        eyebrow: content.eyebrow,
        title: content.title,
        blocks: content.blocks,
        button: {content.button, url(subject_path(kind, p, user.locale))},
        footer: [
          {dgettext("emails", "Manage my alerts"), url(Paths.account(user.locale, :alerts))},
          {dgettext("emails", "Stop this alert"), url(Unsubscribe.path(token))},
          {dgettext("emails", "Unsubscribe from every email"),
           url(Unsubscribe.path(Unsubscribe.token(:all, user.id)))}
        ],
        unsubscribe: url(Unsubscribe.path(token))
      )
    end)
  end

  defp content("rating_change", p, country, _locale) do
    agency = agency(p["agency"])
    action = action(p["action_type"])

    %{
      subject:
        dgettext("emails", "%{country}: %{agency} %{action} the rating, %{rating}",
          agency: agency,
          action: action,
          country: country,
          rating: p["rating"]
        ),
      preheader:
        dgettext("emails", "Decision of %{date} on a country you follow.", date: p["action_date"]),
      eyebrow: dgettext("emails", "Alert · sovereign rating"),
      title: dgettext("emails", "%{agency} on %{country}", agency: agency, country: country),
      blocks:
        [
          {:paragraph,
           dgettext(
             "emails",
             "Followed country: %{country}. %{agency} %{action} its long-term foreign-currency rating.",
             country: country,
             agency: agency,
             action: action
           )},
          {:facts,
           [
             {dgettext("emails", "Rating"), p["rating"]},
             {dgettext("emails", "Outlook"), outlook(p["outlook"])},
             {dgettext("emails", "Date"), p["action_date"]}
           ]}
        ] ++
          source(p["source_url"]) ++
          [{:paragraph, dgettext("emails", "Information, not investment advice.")}],
      button: dgettext("emails", "See %{country}", country: country)
    }
  end

  defp content("new_edition", p, country, _locale) do
    %{
      subject: dgettext("emails", "New IMF figures for %{country}", country: country),
      preheader: p["edition_label"] || p["edition"],
      eyebrow: dgettext("emails", "Alert · new IMF edition"),
      title: dgettext("emails", "New IMF figures for %{country}", country: country),
      blocks: [
        {:paragraph,
         dgettext(
           "emails",
           "The IMF published a new edition (%{edition}); Syli Atlas has it online.",
           edition: p["edition_label"] || p["edition"]
         )},
        {:facts,
         [
           {dgettext("emails", "Real GDP growth %{year}", year: p["year"]),
            percent(p["real_gdp_growth"])},
           {dgettext("emails", "Inflation %{year}", year: p["year"]), percent(p["inflation"])}
         ]},
        {:paragraph, status_note(p["status"], p["year"])}
      ],
      button: dgettext("emails", "See %{country}", country: country)
    }
  end

  defp content("budget_law", p, country, locale) do
    law = budget_law_name(p)
    stage = budget_stage(p["stage"])

    %{
      subject:
        dgettext("emails", "%{country}: %{law} %{stage}",
          country: country,
          law: law,
          stage: stage
        ),
      preheader:
        dgettext(
          "emails",
          "A budget law of a country you follow, checked against the official text."
        ),
      eyebrow: dgettext("emails", "Alert · budget law"),
      title: dgettext("emails", "%{law} of %{country}", law: law, country: country),
      blocks:
        [
          {:paragraph,
           dgettext("emails", "Followed country: %{country}. %{law} is %{stage}.",
             country: country,
             law: law,
             stage: stage
           )},
          {:facts,
           [
             {dgettext("emails", "Expenditure"),
              SyliAtlas.Budgets.Money.short(decimal(p["expenditure"]), p["currency"], locale)},
             {dgettext("emails", "Revenue"),
              SyliAtlas.Budgets.Money.short(decimal(p["revenue"]), p["currency"], locale)},
             {dgettext("emails", "Date"), p["last_date"] || "—"}
           ]}
        ] ++
          if(p["source_url"],
            do: [
              {:paragraph,
               dgettext("emails", "Official text: %{name}, %{url}",
                 name: p["source_name"],
                 url: p["source_url"]
               )}
            ],
            else: []
          ),
      button: dgettext("emails", "See the budget of %{country}", country: country)
    }
  end

  defp content(kind, p, country, _locale) when kind in ["indicator_above", "indicator_below"] do
    indicator = indicator(p["indicator"])
    unit = &with_unit(p["indicator"], &1)
    threshold = unit.(p["threshold"])

    subject =
      if kind == "indicator_below",
        do:
          dgettext("emails", "%{country}: %{indicator} goes below %{threshold}",
            country: country,
            indicator: indicator,
            threshold: threshold
          ),
        else:
          dgettext("emails", "%{country}: %{indicator} goes above %{threshold}",
            country: country,
            indicator: indicator,
            threshold: threshold
          )

    %{
      subject: subject,
      preheader: dgettext("emails", "New IMF edition: your threshold is crossed."),
      eyebrow: dgettext("emails", "Alert · indicator"),
      title: subject,
      blocks: [
        {:paragraph,
         dgettext(
           "emails",
           "The new IMF edition (%{edition}) crosses the threshold of your alert.",
           edition: p["edition_label"] || p["edition"]
         )},
        {:facts,
         [
           {dgettext("emails", "Before (%{year})", year: p["previous_year"]),
            unit.(p["previous"])},
           {dgettext("emails", "Now (%{year})", year: p["year"]), unit.(p["current"])},
           {dgettext("emails", "Your threshold"), threshold}
         ]},
        {:paragraph, status_note(p["status"], p["year"])}
      ],
      button: dgettext("emails", "See %{country}", country: country)
    }
  end

  defp content(kind, p, _country, _locale)
       when kind in ["session_move", "price_above", "price_below"] do
    name = p["name"]
    value = money(p["value"], p["currency"])

    subject =
      case kind do
        "session_move" ->
          dgettext("emails", "%{name}: %{change} on the session",
            name: name,
            change: signed_percent(p["change_pct"])
          )

        "price_above" ->
          dgettext("emails", "%{name} goes above %{price}",
            name: name,
            price: money(p["threshold"], p["currency"])
          )

        "price_below" ->
          dgettext("emails", "%{name} goes below %{price}",
            name: name,
            price: money(p["threshold"], p["currency"])
          )
      end

    rule =
      case kind do
        "session_move" ->
          dgettext("emails", "moves more than %{threshold} in a session",
            threshold: percent(p["threshold"])
          )

        "price_above" ->
          dgettext("emails", "closes above %{price}", price: money(p["threshold"], p["currency"]))

        "price_below" ->
          dgettext("emails", "closes below %{price}", price: money(p["threshold"], p["currency"]))
      end

    %{
      subject: subject,
      preheader:
        dgettext("emails", "Close of %{date}, %{exchange}.",
          date: p["date"],
          exchange: p["exchange_name"]
        ),
      eyebrow: dgettext("emails", "Alert · stock exchange"),
      title: subject,
      blocks: [
        {:paragraph, dgettext("emails", "Your alert: %{name} %{rule}.", name: name, rule: rule)},
        {:facts,
         [
           {if(p["ticker"], do: dgettext("emails", "Close"), else: dgettext("emails", "Index")),
            value},
           {dgettext("emails", "Session"), signed_percent(p["change_pct"])},
           {dgettext("emails", "Date"), p["date"]}
         ]},
        # The credit the licence asks for, verbatim, with its link.
        {:paragraph, credit(p["sources"])},
        {:paragraph,
         dgettext("emails", "Closing prices, not real time. Information, not investment advice.")}
      ],
      button: dgettext("emails", "See %{name}", name: name)
    }
  end

  @doc "The digest of favourites (`SyliAtlas.Accounts.Digests.build/2`)."
  def digest(%User{} = user, digest) do
    in_locale(user.locale, fn ->
      period =
        dgettext("emails", "%{from} to %{to}", from: date(digest.from), to: date(digest.to))

      figures =
        case digest.figures do
          [] ->
            []

          rows ->
            [
              {:paragraph,
               dgettext("emails", "Followed countries · IMF, %{year} (%{status})",
                 year: digest.year,
                 status: status_word(rows |> hd() |> elem(1) |> Map.get("status"))
               )},
              {:facts,
               Enum.map(rows, fn {code, v} ->
                 {country(code, user.locale),
                  dgettext("emails", "growth %{growth}, inflation %{inflation}",
                    growth: percent(v["real_gdp_growth"]),
                    inflation: percent(v["inflation"])
                  )}
               end)}
            ]
        end

      ratings =
        case digest.ratings do
          [] ->
            []

          rows ->
            [
              {:paragraph, dgettext("emails", "Rating decisions")},
              {:facts,
               Enum.map(rows, fn r ->
                 {"#{country(r.country_code, user.locale)} · #{agency(r.agency)}",
                  "#{r.rating} · #{action(r.action_type)} · #{r.action_date}"}
               end)}
            ]
        end

      alerts =
        case digest.deliveries do
          [] ->
            []

          rows ->
            [
              {:paragraph,
               dngettext("emails", "1 alert set off", "%{count} alerts set off", length(rows))},
              {:facts,
               Enum.map(rows, fn d ->
                 {country(d.payload["country_code"], user.locale), line(d)}
               end)}
            ]
        end

      subject =
        if digest.period == "monthly",
          do: dgettext("emails", "Your month on Syli Atlas"),
          else: dgettext("emails", "Your week on Syli Atlas")

      token = Unsubscribe.token(:digest, user.id)

      Emails.compose(user.email, user.locale,
        subject: subject,
        preheader: period,
        eyebrow: dgettext("emails", "Digest · %{period}", period: period),
        title: dgettext("emails", "What moved in your favourites"),
        blocks: figures ++ ratings ++ alerts,
        button: {dgettext("emails", "Open my space"), url(Paths.account(user.locale))},
        footer: [
          {dgettext("emails", "Change the digest"),
           url(Paths.account(user.locale, :security) <> "#emails")},
          {dgettext("emails", "Stop the digest"), url(Unsubscribe.path(token))}
        ],
        unsubscribe: url(Unsubscribe.path(token))
      )
    end)
  end

  # One line of a delivery, in the digest.
  defp line(%AlertDelivery{kind: "rating_change", payload: p}),
    do: "#{agency(p["agency"])} · #{p["rating"]} · #{action(p["action_type"])}"

  defp line(%AlertDelivery{kind: kind, payload: p})
       when kind in ["session_move", "price_above", "price_below"],
       do:
         "#{p["name"]} · #{money(p["value"], p["currency"])} · #{signed_percent(p["change_pct"])} · #{p["date"]}"

  defp line(%AlertDelivery{kind: "budget_law", payload: p}),
    do:
      "#{budget_law_name(p)} · #{budget_stage(p["stage"])} · #{SyliAtlas.Budgets.Money.short(decimal(p["expenditure"]), p["currency"], Gettext.get_locale(SyliAtlasWeb.Gettext))}"

  defp line(%AlertDelivery{kind: "new_edition", payload: p}),
    do: dgettext("emails", "new IMF figures (%{edition})", edition: p["edition"])

  defp line(%AlertDelivery{payload: p}),
    do:
      "#{indicator(p["indicator"])} : #{with_unit(p["indicator"], p["previous"])} → #{with_unit(p["indicator"], p["current"])}"

  # Labels -------------------------------------------------------------------

  @doc false
  def agency("sp"), do: "S&P"
  def agency("moodys"), do: "Moody's"
  def agency("fitch"), do: "Fitch"
  def agency("afcra"), do: "AfCRA"
  def agency(other), do: other

  @doc false
  def action("upgrade"), do: dgettext("emails", "upgrades")
  def action("downgrade"), do: dgettext("emails", "downgrades")
  def action("default"), do: dgettext("emails", "declares a default on")
  def action("outlook_up"), do: dgettext("emails", "raises the outlook of")
  def action("outlook_down"), do: dgettext("emails", "lowers the outlook of")
  def action(_affirmed), do: dgettext("emails", "affirms")

  @doc false
  def outlook("positive"), do: dgettext("emails", "positive")
  def outlook("negative"), do: dgettext("emails", "negative")
  def outlook("stable"), do: dgettext("emails", "stable")
  def outlook("developing"), do: dgettext("emails", "developing")
  def outlook(_none), do: "—"

  defp indicator("real_gdp_growth"), do: dgettext("emails", "real GDP growth")
  defp indicator("inflation"), do: dgettext("emails", "inflation")
  defp indicator("public_debt_pct_gdp"), do: dgettext("emails", "public debt (% of GDP)")
  defp indicator("fiscal_balance_pct_gdp"), do: dgettext("emails", "budget balance (% of GDP)")
  defp indicator("current_account_pct_gdp"), do: dgettext("emails", "current account (% of GDP)")
  defp indicator("gdp_per_capita_usd"), do: dgettext("emails", "GDP per capita (US$)")
  defp indicator("unemployment"), do: dgettext("emails", "unemployment")
  defp indicator(other), do: other

  defp status_note("projection", year),
    do:
      dgettext("emails", "%{year} is an IMF projection: the next edition may revise it.",
        year: year
      )

  defp status_note("estimate", year),
    do:
      dgettext("emails", "%{year} is an IMF estimate: the next edition may revise it.",
        year: year
      )

  defp status_note(_actual, _year), do: dgettext("emails", "Source: IMF, World Economic Outlook.")

  defp status_word("projection"), do: dgettext("emails", "projection")
  defp status_word("estimate"), do: dgettext("emails", "estimate")
  defp status_word(_), do: dgettext("emails", "actual")

  defp source("https://" <> _ = url),
    do: [{:paragraph, dgettext("emails", "Source: the agency's release, %{url}", url: url)}]

  defp source(_none), do: []

  # Numbers as the site writes them in French: a decimal comma.
  defp number(nil), do: "—"

  defp number(value) do
    if Gettext.get_locale(SyliAtlasWeb.Gettext) == "fr",
      do: String.replace(to_string(value), ".", ","),
      else: to_string(value)
  end

  # GDP per capita is in dollars; every other watched indicator is a percentage.
  defp with_unit(_indicator, nil), do: "—"
  defp with_unit("gdp_per_capita_usd", value), do: number(value) <> " $"
  defp with_unit(_indicator, value), do: percent(value)

  defp percent(nil), do: "—"
  defp percent(value), do: number(value) <> " %"

  defp date(%Date{} = d), do: Calendar.strftime(d, "%d/%m/%Y")

  defp country(code, locale) do
    case code && Geo.get_area_by_code(code) do
      nil -> code || "?"
      area -> Geo.Area.name(area, locale)
    end
  end

  defp subject_path(kind, p, locale)
       when kind in ["session_move", "price_above", "price_below"] do
    case p["ticker"] do
      nil -> Paths.exchange(locale, p["exchange"])
      ticker -> Paths.security(locale, p["exchange"], ticker)
    end
  end

  defp subject_path("budget_law", p, locale) do
    case p["country_code"] && Geo.get_area_by_code(p["country_code"]) do
      nil -> Paths.home(locale)
      area -> Paths.area_tab(locale, area, :budget)
    end
  end

  defp subject_path(_kind, p, locale), do: country_path(p["country_code"], locale)

  defp budget_law_name(%{"kind" => "initial", "fiscal_year" => y}),
    do: dgettext("emails", "The %{year} finance law", year: y)

  defp budget_law_name(%{"kind" => "amending", "fiscal_year" => y}),
    do: dgettext("emails", "The amending finance law for %{year}", year: y)

  defp budget_law_name(%{"kind" => "settlement", "fiscal_year" => y}),
    do: dgettext("emails", "The settlement law for %{year}", year: y)

  defp budget_law_name(%{"fiscal_year" => y}),
    do: dgettext("emails", "The provisional budget for %{year}", year: y)

  defp budget_stage("tabled"), do: dgettext("emails", "tabled before the legislature")
  defp budget_stage("voted"), do: dgettext("emails", "voted")
  defp budget_stage("promulgated"), do: dgettext("emails", "promulgated")
  defp budget_stage(_), do: dgettext("emails", "published in the official gazette")

  defp decimal(nil), do: nil
  defp decimal(s) when is_binary(s), do: Decimal.new(s)

  # « Data by MansaAPI (https://mansaapi.com) », as the licence asks next to
  # every figure, exactly as the market pages credit it.
  defp credit(sources) when is_list(sources) and sources != [] do
    sources
    |> Enum.map(fn s ->
      code = s["code"]
      text = SyliAtlas.Market.Catalog.attribution(code)

      case SyliAtlas.Market.Catalog.url(code) || s["url"] do
        nil -> text
        link -> "#{text} (#{link})"
      end
    end)
    |> Enum.uniq()
    |> Enum.join(", ")
  end

  defp credit(_none), do: SyliAtlas.Market.Catalog.attribution("mansa")

  defp signed_percent(nil), do: "—"

  defp signed_percent(value) do
    sign = if String.starts_with?(to_string(value), "-"), do: "", else: "+"
    sign <> percent(value)
  end

  defp money(nil, _currency), do: "—"
  defp money(value, nil), do: number(value)
  defp money(value, currency), do: number(value) <> " " <> currency

  defp country_path(code, locale) do
    case code && Geo.get_area_by_code(code) do
      nil -> Paths.home(locale)
      area -> Paths.area(locale, area)
    end
  end

  defp url(path), do: SyliAtlasWeb.Endpoint.url() <> path

  defp in_locale(locale, fun), do: Gettext.with_locale(SyliAtlasWeb.Gettext, locale, fun)
end
