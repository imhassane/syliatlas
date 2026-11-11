defmodule SyliAtlasWeb.Admin.EmailsHTML do
  use SyliAtlasWeb, :html

  import SyliAtlasWeb.AdminComponents, only: [admin_shell: 1, admin_pager: 1]
  import SyliAtlasWeb.Admin.Format

  embed_templates "emails_html/*"

  def kind_label("rating_change"), do: "Alerte notation"
  def kind_label("new_edition"), do: "Alerte nouvelle édition FMI"
  def kind_label("indicator_above"), do: "Alerte seuil (au-dessus)"
  def kind_label("indicator_below"), do: "Alerte seuil (en dessous)"
  def kind_label("session_move"), do: "Alerte bourse (variation)"
  def kind_label("price_above"), do: "Alerte cours (au-dessus)"
  def kind_label("price_below"), do: "Alerte cours (en dessous)"
  def kind_label("digest"), do: "Récap"
  def kind_label(k), do: k

  def status(:sent), do: {"Envoyé", "pill-ok"}
  def status(:failed), do: {"Échec", "pill-warn"}
  def status(:waiting), do: {"Gardé pour le récap", "pill-neutral"}
  def status(:digested), do: {"Parti dans le récap", "pill-ok"}
  def status(:sending), do: {"En cours d'envoi", "pill-info"}

  @doc "What the email is about, from its frozen payload."
  def about(%{type: :digest, payload: %{"date" => d}}), do: "Récap du #{d}"

  def about(%{payload: p}) do
    [
      p["country_name"] || p["area_name"] || p["country_code"] || p["area_code"],
      p["exchange_name"] || p["security_name"] || p["ticker"],
      p["agency"] && String.upcase(p["agency"]),
      p["rating"],
      p["edition_label"] || p["label"]
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.map_join(" · ", &to_string/1)
    |> case do
      "" -> "—"
      text -> text
    end
  end

  def service_label("resend"), do: "Resend"
  def service_label("smtp " <> where), do: "Mailpit (#{where})"
  def service_label("local"), do: "Boîte locale"
  def service_label("test"), do: "Test"
  def service_label(_), do: "Aucun"
end
