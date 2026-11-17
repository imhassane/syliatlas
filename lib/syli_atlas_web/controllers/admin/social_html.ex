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

  @doc "The link as X shows it: no scheme, no query, cut after 25 characters."
  def x_display_link(url) do
    uri = URI.parse(url)
    shown = String.replace_prefix(uri.host || "", "www.", "") <> (uri.path || "")
    if String.length(shown) > 26, do: String.slice(shown, 0, 25) <> "…", else: shown
  end

  @doc "LinkedIn's text as it will be sent, without the link (shown apart)."
  def linkedin_text(%Post{text_linkedin: text}),
    do: String.replace(text, "lien en premier commentaire", "lien ci-dessous")

  @doc "One of X's action icons (decorative, in the preview)."
  attr :icon, :atom, required: true

  def social_action(assigns) do
    ~H"""
    <svg
      width="18"
      height="18"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.8"
      stroke-linecap="round"
      stroke-linejoin="round"
    >
      <%= case @icon do %>
        <% :reply -> %>
          <path d="M21 12a8 8 0 0 1-11.6 7.1L4 20l1-4.6A8 8 0 1 1 21 12z" />
        <% :repost -> %>
          <path d="M4 9h12l-3-3M20 15H8l3 3" />
        <% :like -> %>
          <path d="M12 20s-7-4.4-7-10a4 4 0 0 1 7-2.6A4 4 0 0 1 19 10c0 5.6-7 10-7 10z" />
        <% :views -> %>
          <path d="M5 20V12M10 20V6M15 20v-9M20 20v-5" />
      <% end %>
    </svg>
    """
  end

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
