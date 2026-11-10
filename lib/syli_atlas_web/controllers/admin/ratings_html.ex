defmodule SyliAtlasWeb.Admin.RatingsHTML do
  use SyliAtlasWeb, :html

  import SyliAtlasWeb.RatingComponents, only: [agency_name: 1, outlook_label: 1]
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

  attr :proposal, :map, required: true
  attr :doc, :map, default: nil

  @doc "The fields of a decision, shared by the queue and the entry form."
  def adm_fields(assigns) do
    ~H"""
    <label>
      Pays
      <select name="p[country_code]" required>
        <option value="">—</option>
        <option :for={{l, v} <- countries(@doc)} value={v} selected={v == @proposal.country_code}>
          {l}
        </option>
      </select>
    </label>
    <label>
      Agence
      <select name="p[agency]" required>
        <option :for={{l, v} <- agencies()} value={v} selected={v == @proposal.agency}>{l}</option>
      </select>
    </label>
    <label>Note <input name="p[rating]" value={@proposal.rating} required placeholder="BB-, B2…" /></label>
    <label>
      Perspective
      <select name="p[outlook]">
        <option :for={{l, v} <- outlooks()} value={v} selected={v == (@proposal.outlook || "")}>
          {l}
        </option>
      </select>
    </label>
    <label>Date <input name="p[action_date]" value={@proposal.action_date} placeholder="AAAA-MM-JJ" /></label>
    <label>
      Décision
      <select name="p[action_type]">
        <option
          :for={{l, v} <- action_types()}
          value={v}
          selected={v == (@proposal.action_type || "")}
        >
          {l}
        </option>
      </select>
    </label>
    <label class="adm-wide">
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
