defmodule SyliAtlasWeb.Admin.RatingsHTML do
  use SyliAtlasWeb, :html

  import SyliAtlasWeb.RatingComponents, only: [agency_name: 1, outlook_label: 1]
  import SyliAtlasWeb.AdminComponents, only: [admin_shell: 1]
  alias SyliAtlas.Ratings.{Proposal, Scale}

  embed_templates "ratings_html/*"

  def agencies, do: [{"S&P", "sp"}, {"Moody's", "moodys"}, {"Fitch", "fitch"}, {"AfCRA", "afcra"}]

  def outlooks,
    do: [
      {"—", ""},
      {"Positive", "positive"},
      {"Stable", "stable"},
      {"Négative", "negative"},
      {"En évolution", "developing"},
      {"Aucune", "none"}
    ]

  def action_types do
    labels = %{
      "upgrade" => "Relèvement",
      "downgrade" => "Abaissement",
      "affirmed" => "Confirmation",
      "outlook_up" => "Perspective relevée",
      "outlook_down" => "Perspective abaissée",
      "outlook" => "Perspective modifiée",
      "default" => "Défaut"
    }

    [{"—", ""} | Enum.map(Proposal.action_types(), &{labels[&1], &1})]
  end

  def countries(nil), do: []

  def countries(doc) do
    doc["countries"]
    |> Map.values()
    |> Enum.sort_by(& &1["name"]["fr"])
    |> Enum.map(&{&1["name"]["fr"], &1["code"]})
  end

  def country_name(doc, code), do: get_in(doc || %{}, ["countries", code, "name", "fr"]) || code

  def current(doc, code, agency) do
    entry = get_in(doc || %{}, ["countries", code])
    entry && Enum.find(entry["agencies"], &(&1["agency"] == agency))
  end

  def warning_label("unknown_country"), do: "pays inconnu"
  def warning_label("wrong_scale"), do: "échelle d'une autre agence (Moody's ≠ S&P/Fitch)"
  def warning_label("same_as_current"), do: "identique à la note en ligne (confirmation ?)"
  def warning_label("big_jump"), do: "écart de 3 crans ou plus avec la note en ligne"
  def warning_label("type_mismatch"), do: "type de décision incohérent avec l'écart de note"
  def warning_label("older_than_current"), do: "plus ancienne que la décision en ligne"
  def warning_label("future_date"), do: "date dans le futur"
  def warning_label("no_date"), do: "date manquante"
  def warning_label(code), do: code

  def origin_label("watch"), do: "veille + IA"
  def origin_label(_), do: "saisie"

  def status_label("approved"), do: "publiée"
  def status_label("rejected"), do: "rejetée"
  def status_label(s), do: s

  def display(rating), do: Scale.display(rating)

  @doc "A rating change (« change ») or a confirmation of the rating online (« confirmation »)."
  def kind(%{action_type: type}, _doc) when type in ["upgrade", "downgrade", "default"],
    do: :change

  def kind(p, doc) do
    cur = current(doc, p.country_code, p.agency)

    if cur && Scale.score(p.rating) && Scale.score(p.rating) != cur["score"],
      do: :change,
      else: :confirmation
  end

  @doc "The label and the colour of the decision's pill."
  def decision_pill(p, doc) do
    cur = current(doc, p.country_code, p.agency)
    diff = cur && Scale.score(p.rating) && Scale.score(p.rating) - cur["score"]

    case {p.action_type, diff} do
      {"default", _} -> {"Défaut", "pill-warn"}
      {"upgrade", _} -> {"Relèvement", "pill-ok"}
      {"downgrade", _} -> {"Dégradation", "pill-warn"}
      {"outlook_up", _} -> {"Perspective relevée", "pill-ok"}
      {"outlook_down", _} -> {"Perspective abaissée", "pill-warn"}
      {"outlook", _} -> {"Perspective modifiée", "pill-info"}
      {_, d} when is_integer(d) and d > 0 -> {"Relèvement", "pill-ok"}
      {_, d} when is_integer(d) and d < 0 -> {"Dégradation", "pill-warn"}
      {"affirmed", _} -> {"Confirmation", "pill-neutral"}
      {_, 0} -> {"Confirmation", "pill-neutral"}
      _ -> {"Nouvelle note", "pill-info"}
    end
  end

  @doc "The checks shown under a proposal: {passed?, label}."
  def checks(p) do
    w = p.warnings || []
    agency = agency_name(p.agency)

    [
      {"unknown_country" not in w, "pays reconnu", "pays inconnu"},
      {"same_as_current" not in w, "changement réel", "identique à la note en ligne"},
      {"wrong_scale" not in w, "note valide sur l'échelle #{agency}",
       "échelle d'une autre agence"},
      {"big_jump" not in w, "moins de 3 crans",
       "3 crans ou plus : à confirmer sur le communiqué"},
      {"type_mismatch" not in w, "type de décision cohérent", "type de décision incohérent"},
      {Enum.all?(~w(no_date future_date older_than_current), &(&1 not in w)), "date plausible",
       date_problem(w)}
    ]
    |> Enum.map(fn {ok?, good, bad} -> {ok?, if(ok?, do: good, else: bad)} end)
  end

  defp date_problem(w) do
    cond do
      "no_date" in w -> "date manquante"
      "future_date" in w -> "date dans le futur"
      true -> "plus ancienne que la décision en ligne"
    end
  end

  @months ~w(janv. févr. mars avr. mai juin juil. août sept. oct. nov. déc.)

  @doc "« 6 nov. 2026 » from a date, a datetime or an ISO string (« 2026-11 » too)."
  def fr_date(nil), do: "—"
  def fr_date(""), do: "date inconnue"
  def fr_date(%DateTime{} = at), do: fr_date(DateTime.to_date(at))
  def fr_date(%Date{} = d), do: "#{d.day} #{Enum.at(@months, d.month - 1)} #{d.year}"

  def fr_date(iso) when is_binary(iso) do
    case String.split(iso, "-") do
      [y, m, d] ->
        fr_date(Date.new!(String.to_integer(y), String.to_integer(m), String.to_integer(d)))

      [y, m] ->
        "#{Enum.at(@months, String.to_integer(m) - 1)} #{y}"

      _ ->
        iso
    end
  rescue
    _ -> iso
  end

  @doc "« Caa2 → Caa1 », « B confirmée » or « Ca (comme en ligne) »."
  def proposal_text(p, nil), do: display(p.rating)

  def proposal_text(p, cur) do
    cond do
      cur["rating"] != p.rating -> "#{display(cur["rating"])} → #{display(p.rating)}"
      p.action_type in [nil, "affirmed"] -> "#{display(p.rating)} confirmée"
      true -> "#{display(p.rating)} (comme en ligne)"
    end
  end

  def source_placeholder("sp"), do: "https://www.spglobal.com/ratings/…"
  def source_placeholder("moodys"), do: "https://ratings.moodys.com/…"
  def source_placeholder("fitch"), do: "https://www.fitchratings.com/research/…"
  def source_placeholder(_), do: "https://…"

  @doc "Countries with at least one rating online."
  def rated_count(nil), do: 0

  def rated_count(doc),
    do: doc["countries"] |> Map.values() |> Enum.count(&((&1["agencies"] || []) != []))

  attr :proposal, :map, required: true
  attr :doc, :map, default: nil
  attr :form, :string, default: nil, doc: "id of the form the fields belong to, when outside it"
  attr :source, :boolean, default: true, doc: "include the agency release link"

  @doc "The fields of a decision, shared by the queue and the entry form."
  def adm_fields(assigns) do
    ~H"""
    <label>
      Pays
      <select form={@form} name="p[country_code]" required>
        <option value="">—</option>
        <option :for={{l, v} <- countries(@doc)} value={v} selected={v == @proposal.country_code}>
          {l}
        </option>
      </select>
    </label>
    <label>
      Agence
      <select form={@form} name="p[agency]" required>
        <option :for={{l, v} <- agencies()} value={v} selected={v == @proposal.agency}>{l}</option>
      </select>
    </label>
    <label>Note
    <input form={@form} name="p[rating]" value={@proposal.rating} required placeholder="BB-, B2…" /></label>
    <label>
      Perspective
      <select form={@form} name="p[outlook]">
        <option :for={{l, v} <- outlooks()} value={v} selected={v == (@proposal.outlook || "")}>
          {l}
        </option>
      </select>
    </label>
    <label>Date
    <input form={@form} name="p[action_date]" value={@proposal.action_date} placeholder="AAAA-MM-JJ" /></label>
    <label>
      Décision
      <select form={@form} name="p[action_type]">
        <option
          :for={{l, v} <- action_types()}
          value={v}
          selected={v == (@proposal.action_type || "")}
        >
          {l}
        </option>
      </select>
    </label>
    <label :if={@source} class="adm-wide">
      Communiqué de l'agence (obligatoire pour publier)
      <input
        name="p[source_url]"
        type="url"
        value={@proposal.source_url}
        placeholder="https://www.fitchratings.com/research/…"
      />
    </label>
    """
  end
end
