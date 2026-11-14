defmodule SyliAtlasWeb.Admin.BudgetsHTML do
  use SyliAtlasWeb, :html

  import SyliAtlasWeb.AdminComponents, only: [admin_shell: 1]
  alias SyliAtlas.Budgets.{Law, Money, Proposal}

  embed_templates "budgets_html/*"

  defdelegate fr_date(d), to: SyliAtlasWeb.Admin.RatingsHTML

  def kinds,
    do: [
      {"Initiale", "initial"},
      {"Rectificative", "amending"},
      {"Règlement", "settlement"},
      {"Provisoire (douzièmes)", "provisional"}
    ]

  def stages,
    do: [
      {"Déposée", "tabled"},
      {"Votée", "voted"},
      {"Promulguée", "promulgated"},
      {"Publiée au JO", "published"}
    ]

  def legislature_kinds,
    do: [
      {"Parlement", "parliament"},
      {"Organe de transition", "transition"},
      {"Aucun (ordonnances)", "none"},
      {"Suspendu", "suspended"}
    ]

  @doc "How a proposal arrived, as shown in its row."
  def origin_label("extraction"), do: "lue par l'IA"
  def origin_label("research"), do: "trouvée par recherche web"
  def origin_label(_), do: "saisie"

  def label(list, value),
    do: Enum.find_value(list, value || "—", fn {l, v} -> v == value && l end)

  def amount(nil, _currency), do: "—"

  def amount(d, currency),
    do: Money.short(d, currency, "fr") <> " · " <> Decimal.to_string(d, :normal)

  def status_label("new"), do: {"En attente", "pill-neutral"}
  def status_label("extracting"), do: {"Lecture IA", "pill-info"}
  def status_label("extracted"), do: {"Lu", "pill-ok"}
  def status_label("failed"), do: {"Échec", "pill-warn"}
  def status_label("no_key"), do: {"Pas de clé IA", "pill-warn"}
  def status_label(other), do: {other, "pill-neutral"}

  def country_name(countries, code) when is_list(countries) do
    case Enum.find(countries, &(&1.code == code)) do
      nil -> code
      a -> SyliAtlas.Geo.Area.name(a, "fr")
    end
  end

  def country_name(countries, code) when is_map(countries) do
    case countries[code] do
      nil -> code
      a -> SyliAtlas.Geo.Area.name(a, "fr")
    end
  end

  def value(%Proposal{} = p, field) do
    case Map.get(p, field) do
      %Decimal{} = d -> Decimal.to_string(d, :normal)
      %Date{} = d -> Date.to_iso8601(d)
      nil -> nil
      v -> v
    end
  end

  def level(overview, code) do
    case Enum.find(overview["countries"], &(&1["code"] == code)) do
      %{"level" => "official"} -> {"Loi officielle", "pill-ok"}
      _ -> {"FMI seulement", "pill-neutral"}
    end
  end

  attr :proposal, Proposal, required: true
  attr :countries, :list, default: nil, doc: "a country list: the country can be chosen"

  @doc "The fields of a law: entry by hand, or the correction of a proposal."
  def law_fields(assigns) do
    ~H"""
    <label :if={@countries}>
      Pays
      <select name="p[country_code]" required>
        <option value="">—</option>
        <option :for={c <- @countries} value={c.code} selected={@proposal.country_code == c.code}>
          {SyliAtlas.Geo.Area.name(c, "fr")}
        </option>
      </select>
    </label>
    <label>
      Exercice
      <input
        name="p[fiscal_year]"
        type="number"
        min="2000"
        max="2100"
        value={value(@proposal, :fiscal_year)}
      />
    </label>
    <label>
      Type
      <select name="p[kind]">
        <option :for={{l, v} <- kinds()} value={v} selected={@proposal.kind == v}>{l}</option>
      </select>
    </label>
    <label>
      Rang (rectificative)
      <input
        name="p[sequence]"
        type="number"
        min="1"
        max="9"
        value={value(@proposal, :sequence) || 1}
      />
    </label>
    <label>
      Étape
      <select name="p[stage]">
        <option :for={{l, v} <- stages()} value={v} selected={@proposal.stage == v}>{l}</option>
      </select>
    </label>
    <label>Numéro <input name="p[reference]" value={value(@proposal, :reference)} /></label>
    <label>Organe qui vote <input name="p[legislature]" value={value(@proposal, :legislature)} /></label>
    <label>Dépôt <input name="p[tabled_on]" type="date" value={value(@proposal, :tabled_on)} /></label>
    <label>Vote <input name="p[voted_on]" type="date" value={value(@proposal, :voted_on)} /></label>
    <label>
      Promulgation
      <input name="p[promulgated_on]" type="date" value={value(@proposal, :promulgated_on)} />
    </label>
    <label>JO <input name="p[published_on]" type="date" value={value(@proposal, :published_on)} /></label>
    <label>Voix pour
    <input name="p[votes_for]" type="number" min="0" value={value(@proposal, :votes_for)} /></label>
    <label>
      Voix contre
      <input name="p[votes_against]" type="number" min="0" value={value(@proposal, :votes_against)} />
    </label>
    <label>
      Recettes (unités)
      <input name="p[revenue]" inputmode="decimal" value={value(@proposal, :revenue)} />
    </label>
    <label>
      Dépenses (unités)
      <input name="p[expenditure]" inputmode="decimal" value={value(@proposal, :expenditure)} />
    </label>
    <label>Devise <input name="p[currency]" maxlength="3" value={value(@proposal, :currency)} /></label>
    <label>
      Nom de la source
      <input
        name="p[source_name]"
        placeholder="Journal officiel de…"
        value={value(@proposal, :source_name)}
      />
    </label>
    <label class="adm-wide">
      Lien du texte officiel (https)
      <input
        name="p[source_url]"
        type="url"
        placeholder="https://"
        value={value(@proposal, :source_url)}
      />
    </label>
    """
  end

  def law_kinds, do: Law.kinds()
end
