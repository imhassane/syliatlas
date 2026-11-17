defmodule SyliAtlasWeb.Admin.SocialHTML do
  use SyliAtlasWeb, :html

  import SyliAtlasWeb.AdminComponents, only: [admin_shell: 1]

  alias SyliAtlas.Geo
  alias SyliAtlas.Geo.Area
  alias SyliAtlas.Social.Post

  embed_templates "social_html/*"

  def kind_label("rating"), do: "Notation"
  def kind_label("budget_law"), do: "Loi de finances"
  def kind_label("edition"), do: "Édition du FMI"
  def kind_label("rebasing"), do: "Rebasage du PIB"
  def kind_label(other), do: other

  def title(%Post{area_code: nil} = p), do: kind_label(p.kind)

  def title(%Post{area_code: code} = p), do: "#{area_name(code)} · #{kind_label(p.kind)}"

  def area_name(code) do
    if area = Geo.get_area_by_code(code), do: Area.name(area, "fr"), else: code
  end

  def agency_name("sp"), do: "S&P"
  def agency_name("moodys"), do: "Moody's"
  def agency_name("fitch"), do: "Fitch"
  def agency_name("afcra"), do: "AfCRA"
  def agency_name(other), do: other

  def x_count(%Post{} = p), do: Post.x_length(p)
  def x_limit, do: Post.x_limit()

  @doc "Outcome of one network: label and pill class."
  def network_state(nil), do: nil
  def network_state("pending"), do: {"En cours d'envoi", "pill-info"}
  def network_state("queued"), do: {"Dans la file Buffer", "pill-ok"}
  def network_state("simulated"), do: {"Simulé", "pill-warn"}
  def network_state("failed"), do: {"Échec", "pill-warn"}
  def network_state(other), do: {other, "pill-neutral"}

  def status_label("rejected"), do: {"Rejeté", "pill-neutral"}
  def status_label("approved"), do: {"En cours", "pill-info"}
  def status_label("done"), do: {"Envoyé", "pill-ok"}
  def status_label(other), do: {other, "pill-neutral"}

  def fr_datetime(nil), do: "—"
  def fr_datetime(%DateTime{} = d), do: Calendar.strftime(d, "%d/%m/%Y %H:%M UTC")

  def service_name("twitter"), do: "X"
  def service_name("linkedin"), do: "LinkedIn"
  def service_name(other), do: other
end
