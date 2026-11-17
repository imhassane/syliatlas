defmodule SyliAtlasWeb.Admin.SocialHTML do
  use SyliAtlasWeb, :html

  import SyliAtlasWeb.AdminComponents, only: [admin_shell: 1]

  alias SyliAtlas.Geo
  alias SyliAtlas.Geo.Area
  alias SyliAtlas.Social
  alias SyliAtlas.Social.{Clock, Post}

  embed_templates "social_html/*"

  def kind_label("rating"), do: "Notation"
  def kind_label("budget_law"), do: "Loi de finances"
  def kind_label("edition"), do: "Édition du FMI"
  def kind_label("rebasing"), do: "Rebasage du PIB"
  def kind_label("national"), do: "Chiffre national"
  def kind_label("page"), do: "Page du site"
  def kind_label(other), do: other

  @doc "A post's name on the board: its country and kind, or a page's first line."
  def title(%Post{kind: "page"} = p) do
    line = (p.text_linkedin || p.text_x || "") |> String.split("\n", parts: 2) |> hd()
    if String.length(line) > 70, do: String.slice(line, 0, 69) <> "…", else: line
  end

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
    do: String.replace(text || "", "lien en premier commentaire", "lien ci-dessous")

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

  @doc "The logo of a network, small."
  attr :network, :string, required: true

  def network_mark(assigns) do
    ~H"""
    <span
      class="soc-net"
      title={network_name(@network)}
      aria-label={network_name(@network)}
      role="img"
    >
      <svg
        :if={@network == "x"}
        width="11"
        height="11"
        viewBox="0 0 24 24"
        fill="currentColor"
        aria-hidden="true"
      ><path d="M18.901 1.153h3.68l-8.04 9.19L24 22.846h-7.406l-5.8-7.584-6.638 7.584H.474l8.6-9.83L0 1.154h7.594l5.243 6.932ZM17.61 20.644h2.039L6.486 3.24H4.298Z" /></svg>
      <span :if={@network == "linkedin"} aria-hidden="true">in</span>
    </span>
    """
  end

  def x_limit, do: Post.x_limit()

  def network_name("x"), do: "X"
  def network_name("linkedin"), do: "LinkedIn"

  @doc "The networks a post goes or went to."
  def networks_of(%Post{status: s} = p) when s in ["draft", "ready"], do: Post.chosen(p)

  def networks_of(%Post{} = p),
    do: for({n, st} <- [{"x", p.x_state}, {"linkedin", p.linkedin_state}], st, do: n)

  @doc "Outcome of one network: label and pill class."
  def network_state(nil), do: nil
  def network_state("waiting"), do: {"En attente", "pill-neutral"}
  def network_state("pending"), do: {"En cours d'envoi", "pill-info"}
  def network_state("queued"), do: {"Dans la file Buffer", "pill-ok"}
  def network_state("sent"), do: {"Publié", "pill-ok"}
  def network_state("simulated"), do: {"Simulé", "pill-warn"}
  def network_state("failed"), do: {"Échec", "pill-warn"}
  def network_state(other), do: {other, "pill-neutral"}

  def fr_datetime(nil), do: "—"
  def fr_datetime(%DateTime{} = d), do: Clock.label(d)

  def when_label(nil), do: nil
  def when_label(%DateTime{} = d), do: Clock.label(d)

  def day_label(%Date{} = d), do: Clock.short_day(d)

  def service_name("twitter"), do: "X"
  def service_name("linkedin"), do: "LinkedIn"
  def service_name(other), do: other

  def due_label(%Post{} = p), do: p |> Social.first_due() |> when_label()

  @doc "When each network went out: « X 10:00 · in 14:00 » when they differ."
  def sent_label(%Post{} = p) do
    times =
      for {n, st, at} <- [
            {"X", p.x_state, p.x_sent_at},
            {"in", p.linkedin_state, p.linkedin_sent_at}
          ],
          st in ["sent", "simulated"],
          do: {n, at || p.sent_at}

    case Enum.uniq_by(times, &elem(&1, 1)) do
      [{_, at}] -> when_label(at)
      [] -> when_label(p.sent_at)
      _ -> Enum.map_join(times, " · ", fn {n, at} -> "#{n} #{when_label(at)}" end)
    end
  end

  @metrics [{"impressions", "vues"}, {"clicks", "clics"}, {"reactions", "réactions"}]

  @doc "Buffer's figures of a sent post, both networks added: [{label, value}]."
  def metrics(%Post{} = p) do
    for {key, label} <- @metrics,
        values = for(m <- [p.x_metrics, p.linkedin_metrics], is_map(m), v = m[key], do: v),
        values != [],
        do: {label, values |> Enum.sum() |> round()}
  end

  def quota_pct(n, limit), do: "#{min(100, round(n * 100 / max(limit, 1)))}%"

  def sync_label(nil), do: "jamais synchronisé depuis le démarrage"

  def sync_label({at, :ok}),
    do: "synchronisé avec Buffer #{ago(at)}"

  def sync_label({at, {:error, message}}),
    do: "synchronisation impossible #{ago(at)} : #{message}"

  defp ago(at) do
    minutes = div(DateTime.diff(DateTime.utc_now(), at), 60)

    cond do
      minutes < 1 -> "à l'instant"
      minutes < 60 -> "il y a #{minutes} min"
      true -> "il y a #{div(minutes, 60)} h"
    end
  end

  def sync_ok?({_, :ok}), do: true
  def sync_ok?(_), do: false

  @doc "A week cell's short text: the posts of the slot."
  def cell_text(%{posts: []}), do: nil

  def cell_text(%{posts: posts}) do
    posts
    |> Enum.group_by(& &1.post.id)
    |> Enum.map_join(" · ", fn {_, [first | _] = list} ->
      nets = Enum.map_join(list, ", ", &if(&1.network == "x", do: "X", else: "in"))
      "#{short_title(first.post)} · #{nets}"
    end)
  end

  defp short_title(%Post{kind: "page"} = p), do: p |> title() |> String.slice(0, 18)
  defp short_title(%Post{area_code: code}) when is_binary(code), do: area_name(code)
  defp short_title(p), do: kind_label(p.kind)
end
