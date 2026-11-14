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
