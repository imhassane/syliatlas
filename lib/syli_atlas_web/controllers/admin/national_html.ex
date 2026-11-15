defmodule SyliAtlasWeb.Admin.NationalHTML do
  use SyliAtlasWeb, :html

  import SyliAtlasWeb.AdminComponents, only: [admin_shell: 1]

  embed_templates "national_html/*"

  @checks [
    {"official_source", "Source officielle"},
    {"in_document", "Phrase retrouvée dans le document"},
    {"two_reads", "Deux extractions concordantes"},
    {"arithmetic", "Arithmétique (monnaie locale ÷ taux)"},
    {"gap_vs_imf", "Écart avec le FMI sous 15 %"},
    {"known_country", "Pays déjà suivi"}
  ]

  def checks, do: @checks

  attr :r, :any, required: true

  @doc "The fields of a rebasing, prefilled with what the watch found."
  def rebasing_fields(assigns) do
    ~H"""
    <div class="adm-rebasing-fields">
      <label>
        Annoncé le
        <input type="date" name="rebasing[announced_on]" value={@r.announced_on} required />
      </label>
      <label>
        Ancienne base <input type="text" name="rebasing[old_base]" value={@r.old_base} required />
      </label>
      <label>
        Nouvelle base <input type="text" name="rebasing[new_base]" value={@r.new_base} required />
      </label>
      <label>
        Révision du PIB (%)
        <input
          type="text"
          name="rebasing[level_change_pct]"
          value={@r.level_change_pct}
          inputmode="decimal"
        />
      </label>
      <label>
        Année du PIB révisé
        <input
          type="number"
          name="rebasing[reference_year]"
          value={@r.reference_year}
          min="2000"
          max="2035"
          placeholder="année précédant l'annonce"
        />
      </label>
      <label class="wide">
        Source (nom)
        <input type="text" name="rebasing[source_name]" value={@r.source_name} required />
      </label>
      <label class="wide">
        Source (lien https, de préférence l'institut)
        <input
          type="url"
          name="rebasing[source_url]"
          value={@r.source_url || @r.article_url}
          required
        />
      </label>
    </div>
    """
  end

  def indicator_name("gdp_usd_bn"), do: "PIB, milliards de dollars"
  def indicator_name("public_debt_pct_gdp"), do: "Dette publique, % du PIB"
  def indicator_name(other), do: other

  def status_label("auto_verified"), do: "Vérifié automatiquement"
  def status_label("pending_review"), do: "En cours de vérification"
  def status_label("verified"), do: "Vérifié par une personne"
  def status_label("rejected"), do: "Rejeté"

  def country_name(code) do
    case SyliAtlas.Geo.get_area_by_code(code) do
      nil -> code
      area -> SyliAtlas.Geo.Area.name(area, "fr")
    end
  end

  def imf_of(doc, f) do
    SyliAtlas.National.figure(
      SyliAtlas.National.for_country(doc, f.country_code),
      f.indicator,
      f.calendar_year
    )
  end

  def num(nil), do: "—"
  def num(v) when is_binary(v), do: num(SyliAtlas.National.Verify.to_float(v))
  def num(v), do: SyliAtlasWeb.Format.number(v * 1.0, 1, "fr")

  def fr_date(nil), do: "—"
  def fr_date(%DateTime{} = d), do: Calendar.strftime(d, "%d/%m/%Y %H:%M")
end
