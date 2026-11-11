defmodule SyliAtlasWeb.Admin.MarketHTML do
  use SyliAtlasWeb, :html

  import SyliAtlasWeb.AdminComponents, only: [admin_shell: 1, admin_tabs: 1, admin_pager: 1]
  import SyliAtlasWeb.Admin.Format
  alias SyliAtlas.Market.Catalog

  embed_templates "market_html/*"

  def severity("high"), do: {"Urgent", "pill-warn"}
  def severity("mid"), do: {"À suivre", "pill-info"}
  def severity(_), do: {"Info", "pill-neutral"}

  def rule_label("index_missing"), do: "Indice absent"
  def rule_label("stale"), do: "Donnée figée"
  def rule_label("suspect_change"), do: "Variation suspecte"
  def rule_label("invalid_price"), do: "Cours invalide"
  def rule_label("abnormal_change"), do: "Variation anormale"
  def rule_label("no_trade"), do: "Pas d'échange"
  def rule_label(rule), do: rule

  @doc "The detail in French, from the issue's data."
  def detail(%{rule: "stale", data: %{"as_of" => d}}) when is_binary(d),
    do: "Aucune séance reçue depuis le #{day(Date.from_iso8601!(d))}"

  def detail(%{rule: "suspect_change", data: %{"change_pct" => c, "ytd_pct" => y}}),
    do: "Variation de la séance #{pct(c)}, identique au cumul depuis le 1er janvier (#{pct(y)})"

  def detail(%{rule: "abnormal_change", data: %{"change_pct" => c}}),
    do: "Variation de #{pct(c)} sur la séance"

  def detail(%{rule: "index_missing"}), do: "La source ne donne pas de valeur pour l'indice"
  def detail(%{rule: "invalid_price"}), do: "Clôture absente ou négative"
  def detail(%{rule: "no_trade"}), do: "Ni variation ni volume sur la séance"
  def detail(%{detail: d}), do: d

  @doc "Session date shown after the detail, except for « stale » (already dated)."
  def session(%{rule: "stale"}), do: nil
  def session(%{trade_date: nil}), do: nil
  def session(%{trade_date: d}), do: " · séance du #{day(d)}"

  defp pct(n) do
    case Float.parse(to_string(n)) do
      {f, _} -> if(f > 0, do: "+", else: "") <> String.replace(decimal(f, 2), "-", "−") <> " %"
      :error -> "#{n} %"
    end
  end

  @doc "What the reader sees while the anomaly is open."
  def effect("index_missing"), do: "« Indice non fourni », pas de courbe"
  def effect("stale"), do: "Badge « ancienne » avec la date"
  def effect("suspect_change"), do: "Badge « à vérifier » à côté de la variation"
  def effect("abnormal_change"), do: "Cours de la séance retenu, l'ancien reste affiché"
  def effect("invalid_price"), do: "Valeur rejetée, l'ancienne reste affichée"
  def effect("no_trade"), do: "« Pas d'échange »"
  def effect(_), do: "—"

  @doc "The main decision for a rule: {action, label}."
  def main_action("abnormal_change"), do: {"publish", "Publier le cours"}
  def main_action("stale"), do: {"retry", "Relancer l'import"}
  def main_action("index_missing"), do: {"accept", "Accepter"}
  def main_action(_), do: {"accept", "Le chiffre est juste"}

  def source_name(nil), do: "—"
  def source_name(code), do: (Catalog.get(code) || %{name: code}).name

  def source_state(%{status: "active"}), do: {"Active", "pill-ok"}
  def source_state(%{status: "planned"}), do: {"Prévue", "pill-neutral"}
  def source_state(%{status: s}), do: {s, "pill-info"}

  def yes_no(true), do: "Oui"
  def yes_no(false), do: "Non"

  def kind_label("aggregator"), do: "Agrégateur"
  def kind_label("official"), do: "Source officielle de la bourse"
  def kind_label(k), do: k

  def fresh_class(nil), do: "pill-neutral"

  def fresh_class(%Date{} = d) do
    if SyliAtlas.Market.Quality.business_days_between(d, Date.utc_today()) > 2,
      do: "pill-warn",
      else: "pill-ok"
  end
end
