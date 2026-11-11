defmodule SyliAtlas.Recaps.Emails do
  @moduledoc """
  The emails of the country recap: the confirmation of a subscription and
  the recap itself, in the subscription's language, laid out by
  `SyliAtlas.Accounts.EmailLayout` like every other Syli Atlas email.
  """
  use Gettext, backend: SyliAtlasWeb.Gettext

  alias SyliAtlas.Accounts.{AlertEmails, Emails}
  alias SyliAtlas.Market.Catalog
  alias SyliAtlas.Recaps
  alias SyliAtlas.Recaps.Subscription
  alias SyliAtlasWeb.{Format, Paths}

  @nbsp " "

  @doc "The confirmation email: what was asked, and the link that confirms it."
  def confirmation(%Subscription{} = sub, choices, token) do
    locale = choices.locale

    in_locale(locale, fn ->
      intro =
        if Subscription.confirmed?(sub),
          do:
            dgettext(
              "emails",
              "This address already receives the Syli Atlas recap. Confirm to replace its countries and frequency with these:"
            ),
          else:
            dgettext(
              "emails",
              "Someone, most likely you, asked for the Syli Atlas recap at this address:"
            )

      Emails.compose(sub.email, locale,
        subject: dgettext("emails", "Confirm your Syli Atlas recap"),
        preheader: dgettext("emails", "One click, and the recap starts."),
        eyebrow: dgettext("emails", "Recap · confirmation"),
        title: dgettext("emails", "Confirm your subscription"),
        blocks: [
          {:paragraph, intro},
          {:facts,
           [
             {dgettext("emails", "Countries"), country_names(choices.countries, locale)},
             {dgettext("emails", "Frequency"), frequency(choices.frequency)}
           ]},
          {:note,
           dngettext(
             "emails",
             "Not you? Do nothing: without a click, nothing is sent and an address never confirmed is deleted within %{count} day.",
             "Not you? Do nothing: without a click, nothing is sent and an address never confirmed is deleted within %{count} days.",
             Recaps.unconfirmed_days()
           )}
        ],
        button: {dgettext("emails", "Confirm my recap"), url(Recaps.confirm_path(token))}
      )
    end)
  end

  @doc "The recap of the chosen countries (`SyliAtlas.Recaps.Content.build/4`)."
  def recap(%Subscription{} = sub, content, manage_token) do
    locale = sub.locale

    in_locale(locale, fn ->
      count = length(content.countries)

      period =
        dgettext("emails", "%{from} to %{to}", from: date(content.from), to: date(content.to))

      blocks =
        [summary(content, locale)] ++
          Enum.flat_map(content.countries, &country_blocks(&1, content, sub.frequency, locale)) ++
          [
            {:small, sources(content, locale)},
            {:small,
             dgettext(
               "emails",
               "You receive this recap because you asked for it on Syli Atlas, without an account. Alerts on a threshold or a share price need a free space."
             )}
          ]

      Emails.compose(sub.email, locale,
        subject: subject(content, sub.frequency),
        preheader: preheader(content),
        eyebrow: dgettext("emails", "Digest · %{period}", period: period),
        title:
          if(sub.frequency == "monthly",
            do:
              dngettext(
                "emails",
                "Your country this month",
                "Your %{count} countries this month",
                count
              ),
            else:
              dngettext(
                "emails",
                "Your country this week",
                "Your %{count} countries this week",
                count
              )
          ),
        blocks: blocks,
        footer:
          [
            {dgettext("emails", "Change my countries"), url(Recaps.manage_path(manage_token))},
            {dgettext("emails", "Stop the recap"), url(Recaps.stop_path(manage_token))}
          ] ++
            Enum.map(content.market_sources, &{Catalog.attribution(&1), Catalog.url(&1)}),
        unsubscribe: url(Recaps.stop_path(manage_token))
      )
    end)
  end

  defp subject(content, frequency) do
    names = Enum.map(content.countries, & &1.name)

    who =
      if length(names) <= 3,
        do: Enum.join(names, ", "),
        else: dgettext("emails", "Your %{count} countries", count: length(names))

    if frequency == "monthly",
      do: dgettext("emails", "%{countries}: your month", countries: who),
      else: dgettext("emails", "%{countries}: your week", countries: who)
  end

  defp preheader(%{summary: s} = content) do
    [
      if(s.decisions > 0,
        do:
          dngettext(
            "emails",
            "%{count} rating decision",
            "%{count} rating decisions",
            s.decisions
          )
      ),
      if(s.exchanges > 0,
        do: dgettext("emails", "exchanges: %{up} up, %{down} down", up: s.up, down: s.down)
      ),
      if(content.new_edition?, do: dgettext("emails", "new IMF figures"))
    ]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> dgettext("emails", "The landmarks of your countries.")
      parts -> Enum.join(parts, " · ")
    end
  end

  defp summary(%{summary: s} = content, locale) do
    ratings =
      if s.decisions == 0,
        do: dgettext("emails", "no decision"),
        else:
          dngettext("emails", "%{count} decision", "%{count} decisions", s.decisions) <>
            " · " <> Enum.join(s.decided, ", ")

    imf =
      cond do
        content.edition == nil ->
          "—"

        content.new_edition? ->
          dgettext("emails", "new edition: %{label}",
            label: edition_name(content.edition, locale)
          )

        true ->
          dgettext("emails", "no new edition (latest: %{label})",
            label: edition_name(content.edition, locale)
          )
      end

    rows =
      [{dgettext("emails", "Ratings"), ratings}] ++
        if(s.exchanges > 0,
          do: [
            {dgettext("emails", "Exchanges"),
             dgettext("emails", "%{up} up, %{down} down", up: s.up, down: s.down)}
          ],
          else: []
        ) ++ [{dgettext("emails", "IMF"), imf}]

    {:facts, rows}
  end

  defp country_blocks(c, content, frequency, locale) do
    decisions =
      Enum.map(c.ratings.decisions, fn r ->
        {:highlight,
         dgettext(
           "emails",
           "%{agency} %{action} its rating: %{rating}, outlook %{outlook} · %{date}",
           agency: AlertEmails.agency(r.agency),
           action: AlertEmails.action(r.action_type),
           rating: r.rating,
           outlook: AlertEmails.outlook(r.outlook),
           date: iso_date(r.action_date)
         )}
      end)

    rating_row =
      if c.ratings.decisions == [] do
        current =
          case c.ratings.current do
            [] -> dgettext("emails", "not rated")
            list -> Enum.map_join(list, ", ", &"#{AlertEmails.agency(&1.agency)} #{&1.rating}")
          end

        [
          {dgettext("emails", "Rating"),
           dgettext("emails", "No decision · %{current}", current: current)}
        ]
      else
        []
      end

    market_row =
      case c.market do
        nil ->
          []

        m ->
          over =
            if frequency == "monthly",
              do: dgettext("emails", "over the month"),
              else: dgettext("emails", "over the week")

          [
            {dgettext("emails", "Exchange"),
             dgettext("emails", "%{index}: %{change} %{over} · close of %{date}",
               index: m.index_name || m.exchange_name,
               change: signed_pct(m.change_pct, locale),
               over: over,
               date: iso_date(m.date)
             )}
          ]
      end

    currency_row =
      case c.currency do
        nil ->
          []

        %{peg: %{anchor: anchor, rate: rate}} = cur ->
          [
            {dgettext("emails", "Currency"),
             dgettext("emails", "%{name}, fixed peg: 1 %{anchor} = %{rate} %{code}",
               name: cur.name,
               anchor: anchor,
               rate: Format.number(rate, 3, locale),
               code: cur.code
             )}
          ]

        %{rate: rate} = cur ->
          [
            {dgettext("emails", "Currency"),
             dgettext("emails", "1 USD = %{rate} %{code}",
               rate: rate(rate, locale),
               code: cur.code
             )}
          ]
      end

    imf = c.imf

    figures =
      if imf == %{} do
        []
      else
        [
          {:figures,
           dgettext("emails", "IMF landmarks, %{year} (%{status})",
             year: content.year,
             status: status(content.status)
           ),
           [
             {dgettext("emails", "Growth"), pct(imf["real_gdp_growth"], locale)},
             {dgettext("emails", "Inflation"), pct(imf["inflation"], locale)},
             {dgettext("emails", "Public debt, % of GDP"),
              pct(imf["public_debt_pct_gdp"], locale)}
           ]}
        ]
      end

    [{:section, c.name, {dgettext("emails", "See the profile"), url(Paths.area(locale, c.area))}}] ++
      decisions ++
      case rating_row ++ market_row ++ currency_row do
        [] -> []
        rows -> [{:facts, rows}]
      end ++ figures
  end

  defp sources(content, locale) do
    imf =
      case content.edition do
        nil ->
          dgettext("emails", "IMF, World Economic Outlook")

        e ->
          dgettext("emails", "IMF, World Economic Outlook (%{label})",
            label: edition_name(e, locale)
          )
      end

    market =
      case content.market_sources do
        [] ->
          ""

        codes ->
          " · " <>
            dgettext(
              "emails",
              "exchanges and exchange rates: %{credit}, closing prices, not real time",
              credit: Enum.map_join(codes, ", ", &Catalog.attribution/1)
            )
      end

    dgettext("emails", "Sources:") <>
      " " <>
      imf <>
      " · " <>
      dgettext("emails", "rating agencies") <>
      market <> ". " <> dgettext("emails", "Information, not investment advice.")
  end

  # Formatting --------------------------------------------------------------

  @months %{
    "fr" =>
      ~w(janvier février mars avril mai juin juillet août septembre octobre novembre décembre),
    "en" =>
      ~w(January February March April May June July August September October November December)
  }

  # "2026-10" → "octobre 2026"; the stored label otherwise.
  defp edition_name(%{code: code, label: label}, locale) do
    with [y, m] <- String.split(code || "", "-"),
         {month, ""} when month in 1..12 <- Integer.parse(m) do
      Enum.at(Map.get(@months, locale, @months["en"]), month - 1) <> " " <> y
    else
      _ -> label
    end
  end

  defp country_names(codes, locale) do
    Enum.map_join(codes, ", ", fn code ->
      case SyliAtlas.Geo.get_area_by_code(code) do
        nil -> code
        area -> SyliAtlas.Geo.Area.name(area, locale)
      end
    end)
  end

  defp frequency("monthly"), do: dgettext("emails", "on the 1st of each month")
  defp frequency(_weekly), do: dgettext("emails", "every Monday")

  defp status("projection"), do: dgettext("emails", "projection")
  defp status("estimate"), do: dgettext("emails", "estimate")
  defp status(_), do: dgettext("emails", "actual")

  defp pct(nil, _locale), do: "—"
  defp pct(v, locale), do: Format.number(v, 1, locale) <> @nbsp <> "%"

  defp signed_pct(v, locale) when v > 0, do: "+" <> pct(v, locale)
  defp signed_pct(v, locale), do: pct(v, locale)

  defp rate(r, locale) when r < 10, do: Format.number(r, 3, locale)
  defp rate(r, locale) when r < 1000, do: Format.number(r, 1, locale)
  defp rate(r, locale), do: Format.number(r, 0, locale)

  defp date(%Date{} = d), do: Calendar.strftime(d, "%d/%m/%Y")

  defp iso_date(iso) when is_binary(iso) do
    case Date.from_iso8601(iso) do
      {:ok, d} -> date(d)
      _ -> iso
    end
  end

  defp iso_date(_), do: "—"

  defp url(path), do: SyliAtlasWeb.Endpoint.url() <> path

  defp in_locale(locale, fun), do: Gettext.with_locale(SyliAtlasWeb.Gettext, locale, fun)
end
