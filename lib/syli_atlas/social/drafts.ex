defmodule SyliAtlas.Social.Drafts do
  @moduledoc """
  Prepares the posts of an event (canvas « Syli Atlas — publication sur X et
  LinkedIn », artboard « Modèles »): X in English with the link in the post,
  LinkedIn in French with the link in the first comment. Always the figure,
  the date and the source; never an opinion on a government.

  Called by `SyliAtlas.Workers.AlertEventWorker` (rating decision, budget
  law, IMF edition) and by `SyliAtlas.National.Rebasings` (rebasing
  published). One draft per event (`key`): calling twice changes nothing. A
  failure here never stops the alerts: it is logged and dropped.
  """
  require Logger

  alias SyliAtlas.Geo
  alias SyliAtlas.Geo.{Area, French}
  alias SyliAtlas.Ratings.{Rating, Scale}
  alias SyliAtlas.Repo
  alias SyliAtlas.Social
  alias SyliAtlasWeb.{Paths, Seo}

  import Ecto.Query

  # Largest economies first when several drafts wait (IMF, GDP in dollars).
  @large ~w(ZAF EGY NGA DZA ETH MAR KEN AGO CIV GHA TZA COD)

  @doc "Runs a draft builder without ever raising: alerts must not depend on it."
  def safely(fun) do
    fun.()
  rescue
    e ->
      Logger.error("social: draft not prepared: " <> Exception.format(:error, e, __STACKTRACE__))
      :error
  end

  # Ratings ------------------------------------------------------------------

  @doc "A rating decision: a post for a change of rating or outlook, none for an affirmation."
  def on_rating(rating_id) do
    with %Rating{} = r <- Repo.get(Rating, rating_id),
         {:ok, attrs} <- rating(r, previous(r)) do
      Social.create_draft(attrs)
    else
      _ -> :skip
    end
  end

  defp previous(%Rating{} = r) do
    Repo.one(
      from p in Rating,
        where:
          p.country_code == ^r.country_code and p.agency == ^r.agency and p.id != ^r.id and
            p.action_date <= ^r.action_date,
        order_by: [desc: p.action_date, desc: p.id],
        limit: 1
    )
  end

  @doc false
  def rating(%Rating{} = r, prev) do
    move = move(r, prev)

    if move == :none do
      :skip
    else
      agency = agency(r.agency)
      en = name(r.country_code, "en")
      fr = name(r.country_code, "fr")
      date = french_date(r.action_date)
      outlook_en = outlook_en(r.outlook)
      outlook_fr = outlook_fr(r.outlook)
      before = prev && prev.rating

      {x, li} =
        case move do
          m when m in [:up, :down] ->
            {verb_en, verb_fr} =
              if m == :up, do: {"upgrades", "relève"}, else: {"downgrades", "abaisse"}

            {"#{agency} #{verb_en} #{en} to #{r.rating}#{if before, do: " (from #{before})"}" <>
               if(outlook_en, do: ", outlook #{outlook_en}.", else: "."),
             "#{agency} #{verb_fr} la note #{French.of(fr)} : " <>
               if(before, do: "#{before} → #{r.rating}", else: r.rating) <>
               if(outlook_fr, do: ", perspective #{outlook_fr}", else: "") <>
               date_suffix(date) <> "."}

          :outlook ->
            {"#{agency} moves #{en}'s outlook to #{outlook_en || "none"} and keeps the rating at #{r.rating}.",
             "#{agency} passe la perspective #{French.of(fr)} à #{outlook_fr || "aucune"} et maintient la note à #{r.rating}" <>
               date_suffix(date) <> "."}

          :new ->
            {"#{agency} rates #{en} #{r.rating}" <>
               if(outlook_en, do: ", outlook #{outlook_en}.", else: "."),
             "#{agency} note #{French.the(fr)} #{r.rating}" <>
               if(outlook_fr, do: ", perspective #{outlook_fr}", else: "") <>
               date_suffix(date) <> "."}
        end

      path_en = Paths.rating("en", slug(r.country_code, "en"))
      path_fr = Paths.rating("fr", slug(r.country_code, "fr"))

      {:ok,
       %{
         key: "rating:#{r.country_code}:#{r.agency}:#{r.action_date}",
         kind: "rating",
         area_code: r.country_code,
         priority: 30 + if(move in [:up, :down], do: 10, else: 0) + size(r.country_code),
         text_x: x <> "\n\nRatings from S&P, Moody's and Fitch, with the full history:",
         text_linkedin:
           li <>
             "\n\nOù en sont les autres agences, et l'historique de toutes les décisions : lien en premier commentaire." <>
             "\n\nSource : communiqué de #{agency}.",
         link_x: link(path_en, "x"),
         link_linkedin: link(path_fr, "linkedin"),
         image_url: Seo.image(path_fr)
       }}
    end
  end

  defp move(%Rating{action_type: "affirmed"}, _prev), do: :none
  defp move(%Rating{action_type: t}, _prev) when t in ~w(upgrade), do: :up
  defp move(%Rating{action_type: t}, _prev) when t in ~w(downgrade default), do: :down

  defp move(%Rating{action_type: t}, _prev) when t in ~w(outlook_up outlook_down outlook),
    do: :outlook

  defp move(%Rating{}, nil), do: :new

  defp move(%Rating{} = r, %Rating{} = p) do
    case {Scale.score(r.rating), Scale.score(p.rating)} do
      {a, b} when is_number(a) and is_number(b) and a > b -> :up
      {a, b} when is_number(a) and is_number(b) and a < b -> :down
      _ -> if r.outlook != p.outlook, do: :outlook, else: :none
    end
  end

  defp agency("sp"), do: "S&P"
  defp agency("moodys"), do: "Moody's"
  defp agency("fitch"), do: "Fitch"
  defp agency("afcra"), do: "AfCRA"
  defp agency(other), do: other

  defp outlook_en(o) when o in ~w(positive negative stable developing), do: o
  defp outlook_en(_), do: nil

  defp outlook_fr("positive"), do: "positive"
  defp outlook_fr("negative"), do: "négative"
  defp outlook_fr("stable"), do: "stable"
  defp outlook_fr("developing"), do: "en évolution"
  defp outlook_fr(_), do: nil

  # Budget laws --------------------------------------------------------------

  @doc "A budget law approved: one post per law, at the first stage voted or later."
  def on_budget_law(law_id) do
    with %{} = law <- SyliAtlas.Budgets.get_law(law_id),
         {:ok, attrs} <- budget_law(law) do
      Social.create_draft(attrs)
    else
      _ -> :skip
    end
  end

  @doc false
  def budget_law(law) do
    if law.stage in ~w(voted promulgated published) and law.kind in ~w(initial amending) do
      en = name(law.country_code, "en")
      fr = name(law.country_code, "fr")
      year = law.fiscal_year
      amending? = law.kind == "amending"

      {verb_en, verb_fr} =
        case law.stage do
          "voted" -> {"voted", "a voté"}
          "promulgated" -> {"signed into law", "a promulgué"}
          "published" -> {"published", "a publié"}
        end

      spend = law.expenditure && Decimal.to_float(law.expenditure)

      amount_en =
        if spend,
          do: ": #{amount(spend, law.currency, "en")} of spending",
          else: ""

      amount_fr =
        if spend,
          do: " : #{amount(spend, law.currency, "fr")} de dépenses",
          else: ""

      what_en = if amending?, do: "amended #{year} budget", else: "#{year} budget"

      what_fr =
        if amending?, do: "loi de finances rectificative #{year}", else: "loi de finances #{year}"

      who_fr = French.bindings(fr, "fr")[:The_name]

      path_en = Paths.country_tab("en", slug(law.country_code, "en"), :budget)
      path_fr = Paths.country_tab("fr", slug(law.country_code, "fr"), :budget)

      {:ok,
       %{
         key: "budget_law:#{law.country_code}:#{year}:#{law.kind}:#{law.sequence}",
         kind: "budget_law",
         area_code: law.country_code,
         priority: 20 + size(law.country_code),
         text_x:
           "#{en}'s #{what_en} is #{verb_en}#{amount_en}.\n\nRevenue, deficit and the full law:",
         text_linkedin:
           "#{who_fr} #{verb_fr} sa #{what_fr}#{amount_fr}." <>
             "\n\nRecettes, déficit et texte de la loi : lien en premier commentaire." <>
             if(law.source_name, do: "\n\nSource : #{law.source_name}.", else: ""),
         link_x: link(path_en, "x"),
         link_linkedin: link(path_fr, "linkedin"),
         image_url: Seo.image(path_fr)
       }}
    else
      :skip
    end
  end

  # IMF editions -------------------------------------------------------------

  @doc "A new IMF edition: the five fastest-growing economies forecast."
  def on_edition(edition_id, today \\ Date.utc_today()) do
    year = if today.month >= 7, do: today.year + 1, else: today.year
    en = top_growth(year, "en")
    fr = top_growth(year, "fr")

    case {en, fr} do
      {[_, _, _ | _], [_, _, _ | _]} -> Social.create_draft(edition(edition_id, year, en, fr))
      _ -> :skip
    end
  end

  defp top_growth(year, locale) do
    SyliAtlasWeb.PublicData.ranking("real_gdp_growth", year, year, mode: "value", locale: locale)
    |> Enum.filter(&is_number(&1["value"]))
    |> Enum.take(5)
  rescue
    _ -> []
  end

  @doc false
  def edition(edition_id, year, en, fr) do
    path_en = SyliAtlasWeb.Topics.ranking_path("en", "real_gdp_growth")
    path_fr = SyliAtlasWeb.Topics.ranking_path("fr", "real_gdp_growth")

    lines_en =
      en
      |> Enum.take(3)
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {c, i} -> "#{i}. #{c["name"]} #{pct(c["value"], "en")}" end)

    list_fr =
      fr |> Enum.take(3) |> Enum.map_join(", ", &"#{&1["name"]} (#{pct(&1["value"], "fr")})")

    %{
      key: "edition:#{edition_id}",
      kind: "edition",
      priority: 35,
      text_x:
        "New IMF forecasts: Africa's fastest-growing economies in #{year}\n#{lines_en}\n\nAll 54 countries:",
      text_linkedin:
        "Le FMI publie ses nouvelles prévisions. Les plus fortes croissances attendues en Afrique en #{year} : #{list_fr}." <>
          "\n\nLe classement des 54 pays : lien en premier commentaire." <>
          "\n\nSource : FMI, Perspectives de l'économie mondiale.",
      link_x: link(path_en, "x"),
      link_linkedin: link(path_fr, "linkedin"),
      image_url: Seo.image(path_fr)
    }
  end

  # Rebasings ----------------------------------------------------------------

  @doc "A GDP rebasing published in the admin."
  def on_rebasing(%{status: "published"} = r) do
    en = name(r.country_code, "en")
    fr = name(r.country_code, "fr")
    change = r.level_change_pct && parse(r.level_change_pct)

    {x, li} =
      case change do
        c when is_number(c) and c > 0 ->
          {"#{en} rebases its GDP#{base(r, "en")}: the economy is #{pct(c, "en")} larger than previously measured.",
           "#{French.bindings(fr, "fr")[:The_name]} change l'année de base de ses comptes nationaux#{base(r, "fr")} : le PIB est réévalué de #{pct(c, "fr")}."}

        _ ->
          {"#{en} rebases its GDP#{base(r, "en")}.",
           "#{French.bindings(fr, "fr")[:The_name]} change l'année de base de ses comptes nationaux#{base(r, "fr")}."}
      end

    path_en = Paths.country_tab("en", slug(r.country_code, "en"), :economy)
    path_fr = Paths.country_tab("fr", slug(r.country_code, "fr"), :economy)

    Social.create_draft(%{
      key: "rebasing:#{r.country_code}:#{r.announced_on}",
      kind: "rebasing",
      area_code: r.country_code,
      priority: 30 + size(r.country_code),
      text_x: x <> "\n\nWhat changes, and the official figures:",
      text_linkedin:
        li <>
          "\n\nCe que ça change pour la dette rapportée au PIB et pour le classement : lien en premier commentaire." <>
          if(r.source_name, do: "\n\nSource : #{r.source_name}.", else: ""),
      link_x: link(path_en, "x"),
      link_linkedin: link(path_fr, "linkedin"),
      image_url: Seo.image(path_fr)
    })
  end

  def on_rebasing(_), do: :skip

  defp base(%{new_base: new} = r, "en") when is_binary(new) and new != "",
    do: " (base year #{if r.old_base, do: "#{r.old_base} → "}#{new})"

  defp base(%{new_base: new} = r, "fr") when is_binary(new) and new != "",
    do: " (#{if r.old_base, do: "#{r.old_base} → "}#{new})"

  defp base(_, _), do: ""

  # Helpers ------------------------------------------------------------------

  defp name(code, locale), do: Area.name(area!(code), locale)
  defp slug(code, locale), do: Area.slug(area!(code), locale)

  defp area!(code),
    do: Geo.get_area_by_code(code) || raise(ArgumentError, "unknown area #{inspect(code)}")

  defp link(path, source), do: Seo.url(path) <> "?utm_source=#{source}&utm_medium=social"

  # « 7,346 billion CFA francs », « 7 346 milliards de francs CFA ».
  defp amount(value, currency, locale) do
    {v, unit} =
      cond do
        abs(value) >= 1.0e9 ->
          {value / 1.0e9, if(locale == "fr", do: "milliards", else: "billion")}

        abs(value) >= 1.0e6 ->
          {value / 1.0e6, if(locale == "fr", do: "millions", else: "million")}

        true ->
          {value, nil}
      end

    decimals = if abs(v) >= 100, do: 0, else: 1
    number = SyliAtlasWeb.Format.number(v, decimals, locale)

    money =
      case {currency, locale} do
        {c, "fr"} when c in ~w(XOF XAF) -> "de francs CFA"
        {c, _} when c in ~w(XOF XAF) -> "CFA francs"
        {c, "fr"} when unit != nil -> "de " <> c
        {c, _} -> c
      end

    Enum.join(Enum.reject([number, unit, money], &is_nil/1), " ")
  end

  defp size(code), do: if(code in @large, do: 5, else: 0)

  defp pct(v, "en"), do: :erlang.float_to_binary(v * 1.0, decimals: 1) <> "%"

  defp pct(v, "fr"),
    do: String.replace(:erlang.float_to_binary(v * 1.0, decimals: 1), ".", ",") <> " %"

  defp parse(text) do
    case Float.parse(String.replace(text, ",", ".")) do
      {v, _} -> v
      :error -> nil
    end
  end

  @months ~w(janv. févr. mars avr. mai juin juil. août sept. oct. nov. déc.)

  defp french_date(iso) do
    case Date.from_iso8601(iso || "") do
      {:ok, d} -> "#{d.day} #{Enum.at(@months, d.month - 1)} #{d.year}"
      _ -> nil
    end
  end

  defp date_suffix(nil), do: ""
  defp date_suffix(date), do: " (#{date})"
end
