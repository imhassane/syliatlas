defmodule SyliAtlas.Admin.DailyDigest do
  @moduledoc """
  The administrators' daily email (« Point du jour »): what waits for a
  decision in the administration, what was done automatically (companies
  hidden or confirmed), yesterday's audience (Plausible) and Google
  results (Search Console, two days late), and the state of the platform.

  In French, like the administration. Sent every morning by
  SyliAtlas.Workers.DailyDigestWorker to every active administrator, or to
  `ADMIN_DIGEST_TO` when set.
  """
  import Ecto.Query

  alias SyliAtlas.Accounts.{Emails, User}
  alias SyliAtlas.{Plausible, Repo}

  @doc "Today's date in Paris (the site's day in Plausible): UTC+1, UTC+2 in summer time."
  def paris_today(now \\ DateTime.utc_now()) do
    offset = if summer_time?(now), do: 2, else: 1
    now |> DateTime.add(offset * 3600, :second) |> DateTime.to_date()
  end

  # European summer time: from the last Sunday of March to the last Sunday
  # of October, at 01:00 UTC.
  defp summer_time?(%DateTime{year: y} = now) do
    start = last_sunday(y, 3)
    stop = last_sunday(y, 10)

    DateTime.compare(now, DateTime.new!(start, ~T[01:00:00])) != :lt and
      DateTime.compare(now, DateTime.new!(stop, ~T[01:00:00])) == :lt
  end

  defp last_sunday(year, month) do
    last = Date.new!(year, month, Calendar.ISO.days_in_month(year, month))
    Date.add(last, -rem(Date.day_of_week(last), 7))
  end

  @doc "Everything the email shows, for the day before `today`."
  def build(today \\ paris_today()) do
    day = Date.add(today, -1)
    week_before = Date.add(day, -7)
    since = DateTime.new!(day, ~T[00:00:00]) |> DateTime.add(-3600, :second)

    %{
      day: day,
      items: SyliAtlas.Admin.Queue.items(),
      companies: SyliAtlas.Companies.summary(since),
      audience: audience(day, week_before),
      google: google(),
      members: Repo.aggregate(from(u in User, where: u.inserted_at >= ^since), :count),
      failures: SyliAtlas.Admin.Jobs.failures(1),
      email_failures: SyliAtlas.Admin.Emails.failures(1)
    }
  end

  defp audience(day, week_before) do
    with {:ok, now} <- Plausible.day(day),
         {:ok, before} <- Plausible.day(week_before),
         {:ok, pages} <- Plausible.top_pages(day, 5),
         {:ok, sources} <- Plausible.sources(day) do
      {:ok, %{now: now, before: before, pages: pages, sources: Enum.take(sources, 6)}}
    end
  end

  defp google do
    case SyliAtlas.SearchConsole.daily(10) do
      [] -> nil
      days -> %{last: List.last(days), week_before: Enum.at(days, -8)}
    end
  end

  @doc "Who receives it: `ADMIN_DIGEST_TO` (comma separated) or the active administrators."
  def recipients do
    case Application.get_env(:syli_atlas, __MODULE__, [])[:to] do
      list when is_list(list) and list != [] ->
        list

      _ ->
        Repo.all(
          from u in User,
            where: u.role == "admin" and is_nil(u.deactivated_at),
            select: u.email
        )
    end
  end

  @doc "Sends the email to each recipient. Returns the number sent."
  def deliver(data \\ build()) do
    recipients()
    |> Enum.map(fn to -> to |> email(data) |> Emails.deliver() end)
    |> Enum.count(&(&1 == :ok))
  end

  @doc "The email for one recipient."
  def email(to, data) do
    Gettext.with_locale(SyliAtlasWeb.Gettext, "fr", fn ->
      Emails.compose(to, "fr",
        subject: subject(data),
        preheader: preheader(data),
        eyebrow: "Point du jour · " <> day_text(Date.add(data.day, 1)),
        title: title(data),
        blocks: blocks(data),
        footer: [
          {"Administration", url("/admin")},
          {"Plausible", "https://plausible.io/syliatlas.com"}
        ]
      )
    end)
  end

  # Text --------------------------------------------------------------------

  defp actions(data), do: Enum.sum(Enum.map(data.items, & &1.count))

  defp visits(%{audience: {:ok, a}}), do: a.now.visits
  defp visits(_), do: nil

  @doc false
  def subject(data) do
    n = actions(data)
    first = if n == 0, do: "Rien à valider", else: plural(n, "action", "actions")

    # The development site sends it too: its subject says so.
    prefix =
      if SyliAtlasWeb.Endpoint.host() == "syliatlas.com",
        do: "",
        else: "[#{SyliAtlasWeb.Endpoint.host()}] "

    case visits(data) do
      nil -> prefix <> "Syli Atlas · #{first}"
      v -> prefix <> "Syli Atlas · #{first} · #{plural(v, "visite", "visites")} hier"
    end
  end

  defp title(data) do
    case actions(data) do
      0 -> "Rien n'attend de décision"
      n -> plural(n, "action vous attend", "actions vous attendent")
    end
  end

  defp preheader(data) do
    [
      data.items
      |> Enum.take(2)
      |> Enum.map_join(" · ", &"#{&1.count} #{String.downcase(&1.label)}"),
      length(data.companies.hidden) > 0 &&
        plural(length(data.companies.hidden), "entreprise masquée", "entreprises masquées"),
      visits(data) && "#{plural(visits(data), "visite", "visites")} hier"
    ]
    |> Enum.filter(&(&1 not in [nil, false, ""]))
    |> Enum.join(" · ")
  end

  defp blocks(data) do
    [{:paragraph, summary(data)}] ++
      [{:section, "À valider", {"Tout voir", url("/admin")}}] ++
      if(data.items == [],
        do: [{:paragraph, "Rien à valider aujourd'hui."}],
        else: [{:actions, Enum.map(data.items, &action/1)}]
      ) ++
      [{:section, "Fait automatiquement", nil}] ++
      automatic(data) ++
      [{:section, "Statistiques d'hier", {"Plausible", "https://plausible.io/syliatlas.com"}}] ++
      audience_blocks(data) ++
      google_blocks(data) ++
      [
        {:facts,
         [
           {"Nouveaux membres", int(data.members)},
           {"Tâches en échec (24 h)", int(data.failures)},
           {"E-mails en échec (24 h)", int(data.email_failures)}
         ]}
      ]
  end

  defp summary(data) do
    visits =
      case data.audience do
        {:ok, a} ->
          "Hier, #{plural(a.now.visits, "visite", "visites")}" <>
            with_delta(a.now.visits, a.before.visits, " sur une semaine") <> ". "

        _ ->
          ""
      end

    waiting =
      case actions(data) do
        0 ->
          "Rien n'attend de décision."

        n ->
          "#{plural(n, "élément attend", "éléments attendent")} une décision dans l'administration."
      end

    visits <> waiting
  end

  defp action(i) do
    age = i.oldest && Date.diff(Date.utc_today(), DateTime.to_date(i.oldest))

    %{
      count: i.count,
      label: i.label,
      detail:
        cond do
          is_nil(age) -> ""
          age <= 0 -> "nouveau"
          true -> "le plus ancien attend depuis #{plural(age, "jour", "jours")}"
        end,
      urgent: is_integer(age) and age >= 2,
      url: url(i.path)
    }
  end

  defp automatic(data) do
    c = data.companies

    hidden =
      for h <- c.hidden do
        {:note, "Entreprise masquée : #{h.name} (#{h.country}) — #{h.note || "non confirmée"}."}
      end

    hidden ++
      [
        {:paragraph,
         "#{plural(c.confirmed, "entreprise confirmée par sa source", "entreprises confirmées par leur source")} · " <>
           "#{plural(c.counts["published"] || 0, "affichée", "affichées")} en tout sur les pages produits."}
      ]
  end

  defp audience_blocks(%{audience: {:ok, a}}) do
    [
      {:figures, "Hier · comparé au même jour la semaine d'avant",
       [
         {"Visites", int(a.now.visits) <> with_delta(a.now.visits, a.before.visits, "")},
         {"Pages vues",
          int(a.now.pageviews) <> with_delta(a.now.pageviews, a.before.pageviews, "")},
         {"Durée moyenne", duration(a.now.visit_duration)}
       ]},
      {:rows, "Pages les plus vues", for({path, n} <- a.pages, do: {path, int(n), ""})},
      {:rows, "D'où viennent les visites",
       for({source, n} <- a.sources, do: {source_label(source), int(n), pct(n, a.now.visits)})}
    ]
  end

  defp audience_blocks(%{audience: {:error, :no_api_key}}),
    do: [{:note, "Statistiques indisponibles : la variable PLAUSIBLE_API_KEY est absente."}]

  defp audience_blocks(_),
    do: [{:note, "Statistiques indisponibles : Plausible n'a pas répondu ce matin."}]

  defp google_blocks(%{google: %{last: d} = g}) do
    before = g.week_before

    [
      {:highlight,
       "Google, #{day_text(d.date)} (publié avec deux jours de retard) : #{int(d.clicks)} clics" <>
         if(before, do: with_delta(d.clicks, before.clicks, ""), else: "") <>
         " · #{int(d.impressions)} impressions · position moyenne #{SyliAtlasWeb.Format.number(d.position || 0, 1, "fr")}"}
    ]
  end

  defp google_blocks(_), do: []

  defp source_label(:direct), do: "Accès direct"
  defp source_label(:assistants), do: "Assistants IA (ChatGPT, Perplexity, Claude…)"
  defp source_label(s), do: s

  # Formats -----------------------------------------------------------------

  defp int(n) when is_integer(n), do: SyliAtlasWeb.Format.number(n, 0, "fr")
  defp int(n) when is_float(n), do: SyliAtlasWeb.Format.number(n, 0, "fr")
  defp int(_), do: "0"

  # French: 0 and 1 take the singular.
  defp plural(n, one, _many) when n in [0, 1], do: "#{n} #{one}"
  defp plural(n, _one, many), do: "#{int(n)} #{many}"

  @doc false
  def delta(_now, before) when before in [nil, 0], do: nil

  def delta(now, before) do
    change = (now - before) / before * 100
    sign = if change >= 0, do: "+", else: "−"
    "#{sign}#{SyliAtlasWeb.Format.number(abs(change), 0, "fr")} %"
  end

  defp with_delta(now, before, suffix) do
    case delta(now, before) do
      nil -> ""
      d -> " (#{d}#{suffix})"
    end
  end

  defp pct(_n, total) when total in [nil, 0], do: ""
  defp pct(n, total), do: "#{SyliAtlasWeb.Format.number(100 * n / total, 0, "fr")} %"

  defp duration(seconds) when is_number(seconds) do
    s = round(seconds)
    "#{div(s, 60)} min #{String.pad_leading(Integer.to_string(rem(s, 60)), 2, "0")}"
  end

  defp duration(_), do: "—"

  @months ~w(janvier février mars avril mai juin juillet août septembre octobre novembre décembre)
  @days ~w(lundi mardi mercredi jeudi vendredi samedi dimanche)

  @doc false
  def day_text(%Date{} = d),
    do: "#{Enum.at(@days, Date.day_of_week(d) - 1)} #{d.day} #{Enum.at(@months, d.month - 1)}"

  defp url(path), do: SyliAtlasWeb.Endpoint.url() <> path
end
