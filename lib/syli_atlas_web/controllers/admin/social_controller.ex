defmodule SyliAtlasWeb.Admin.SocialController do
  @moduledoc """
  Admin « Réseaux » (canvas « Syli Atlas — publication sur X et LinkedIn »,
  artboard C): the board of the posts (À valider, En file, Programmés,
  Publiés) under Buffer's state (accounts, quota, the week's slots); the
  composer of a post, for a draft or for any page of the site (« Partager sur
  les réseaux », from the admin bar of the page). Nothing leaves without
  approval.
  """
  use SyliAtlasWeb, :controller

  alias SyliAtlas.Social
  alias SyliAtlas.Social.{Clock, Pages, Post, Writer}

  def index(conn, _params) do
    render(conn, :index,
      page_title: "Admin · Réseaux",
      board: Social.board(),
      stats: Social.stats(),
      quota: Social.quota(),
      full: Social.full_networks(),
      channels: Social.channels(),
      week: Social.week(),
      next_slot: Social.next_slot_label(Post.networks()),
      last_sync: Social.last_sync(),
      candidates: SyliAtlas.Social.Drafts.rating_candidates()
    )
  end

  # The composer ----------------------------------------------------------------

  @doc "« Partager sur les réseaux »: the page's post, ready to edit, or the field to give a page."
  def share(conn, %{"page" => input}) when input != "" do
    with {:ok, path} <- Pages.normalize(input),
         {:ok, page} <- Pages.describe(path) do
      render_composer(conn, page, Pages.draft(page), Post.networks())
    else
      {:error, message} ->
        conn |> put_flash(:error, message) |> render_picker(input)
    end
  end

  def share(conn, _params), do: render_picker(conn, "")

  def create_share(conn, %{"page" => input} = params) do
    networks = networks(params)

    with {:ok, path} <- Pages.normalize(input),
         {:ok, page} <- Pages.describe(path) do
      attrs = Pages.draft(page)

      case params["action"] do
        "propose" ->
          case Writer.propose(page) do
            {:ok, texts} ->
              render_composer(conn, page, Pages.draft(page, texts), networks)

            {:error, message} ->
              conn
              |> put_flash(:error, message)
              |> render_composer(page, Map.merge(attrs, texts(params, attrs)), networks)
          end

        action ->
          case Social.share_page(attrs, texts(params, attrs), networks, action, reviewer(conn)) do
            {:ok, post} ->
              conn |> put_flash(:info, done_message(action, post)) |> back()

            {:error, %Ecto.Changeset{} = cs} ->
              conn
              |> put_flash(:error, errors(cs))
              |> render_composer(page, Map.merge(attrs, texts(params, attrs)), networks)

            {:error, :no_network} ->
              conn
              |> put_flash(:error, "Choisissez au moins un réseau.")
              |> render_composer(page, Map.merge(attrs, texts(params, attrs)), networks)

            {:error, _} ->
              conn |> put_flash(:error, "Ce post n'a pas pu être enregistré.") |> back()
          end
      end
    else
      {:error, message} -> conn |> put_flash(:error, message) |> render_picker(input)
    end
  end

  def create_share(conn, _params), do: render_picker(conn, "")

  @doc "The composer of a draft or of a post in the queue."
  def edit(conn, %{"id" => id}) do
    post = Social.get!(id)

    if post.status in ["draft", "ready"] do
      render(conn, :composer,
        page_title: "Admin · Réseaux · Modifier",
        post: post,
        page: nil,
        action: ~p"/admin/reseaux/#{post.id}",
        networks: Post.chosen(post),
        next_slot: Social.next_slot_label(Post.chosen(post)),
        full: Social.full_networks(),
        simulated: SyliAtlas.Social.Publisher.simulated?()
      )
    else
      conn |> put_flash(:error, "Ce post est déjà parti.") |> back()
    end
  end

  defp render_composer(conn, page, attrs, networks) do
    post = struct(Post, Map.take(attrs, Post.__schema__(:fields)))

    render(conn, :composer,
      page_title: "Admin · Réseaux · Partager une page",
      post: post,
      page: page,
      action: ~p"/admin/reseaux/partager",
      networks: networks,
      next_slot: Social.next_slot_label(networks),
      full: Social.full_networks(),
      simulated: SyliAtlas.Social.Publisher.simulated?(),
      writer: Writer.configured?()
    )
  end

  defp render_picker(conn, input) do
    render(conn, :picker, page_title: "Admin · Réseaux · Partager une page", input: input)
  end

  @doc "For the admin bar of a public page: where its latest post stands."
  def page_state(conn, %{"chemin" => path}) do
    state =
      case Social.latest_for_page(path) do
        nil -> "jamais partagée"
        post -> page_state_label(post)
      end

    conn
    |> put_resp_header("cache-control", "private, no-store")
    |> json(%{state: state, share: ~p"/admin/reseaux/partager?#{[page: path]}"})
  end

  def page_state(conn, _params), do: conn |> put_status(400) |> json(%{error: "chemin"})

  defp page_state_label(%Post{status: "draft"}), do: "à valider"
  defp page_state_label(%Post{status: "ready"}), do: "en file"

  defp page_state_label(%Post{} = p) do
    cond do
      due = Social.first_due(p) -> "programmée #{Clock.label(due)}"
      sent = Social.last_sent(p) -> "partagée #{Clock.label(sent)}"
      true -> "en cours d'envoi"
    end
  end

  # Actions on a post ---------------------------------------------------------

  def prepare_rating(conn, %{"rating_id" => id}) do
    case SyliAtlas.Social.Drafts.on_rating(String.to_integer(id)) do
      {:ok, _} ->
        conn |> put_flash(:info, "Brouillon préparé.") |> back()

      :exists ->
        conn |> put_flash(:info, "Cette décision a déjà son post.") |> back()

      _ ->
        conn
        |> put_flash(:error, "Pas de post pour cette décision (confirmation sans changement).")
        |> back()
    end
  end

  @doc "The composer's form: save the texts, then what the button asked."
  def update(conn, %{"id" => id} = params) do
    post = Social.get!(id)
    attrs = params["post"] || %{}
    networks = if params["reseaux"], do: networks(params), else: Post.chosen(post)
    who = reviewer(conn)

    result =
      case params["action"] do
        "queue" -> Social.put_ready(post, networks, attrs, who)
        "schedule" -> Social.approve(post, networks, attrs, who)
        "now" -> Social.approve(post, networks, attrs, who, :now)
        _ -> Social.update_texts(post, attrs)
      end

    case result do
      {:ok, post} ->
        conn |> put_flash(:info, done_message(params["action"] || "save", post)) |> back()

      {:error, %Ecto.Changeset{} = cs} ->
        conn |> put_flash(:error, errors(cs)) |> redirect(to: ~p"/admin/reseaux/#{id}/modifier")

      {:error, :no_network} ->
        conn
        |> put_flash(:error, "Choisissez au moins un réseau.")
        |> redirect(to: ~p"/admin/reseaux/#{id}/modifier")

      {:error, _} ->
        conn |> put_flash(:error, "Ce post n'est plus modifiable.") |> back()
    end
  end

  @doc "« Programmer » from the board (both networks, one, or those chosen)."
  def approve(conn, %{"id" => id} = params) do
    post = Social.get!(id)

    networks =
      case params["reseaux"] do
        "x" -> ["x"]
        "linkedin" -> ["linkedin"]
        _ -> Post.chosen(post)
      end

    case Social.approve(post, networks, params["post"] || %{}, reviewer(conn)) do
      {:ok, post} ->
        conn |> put_flash(:info, done_message("schedule", post)) |> back()

      {:error, %Ecto.Changeset{} = cs} ->
        conn |> put_flash(:error, errors(cs)) |> back()

      {:error, _} ->
        conn |> put_flash(:error, "Ce post n'est plus un brouillon.") |> back()
    end
  end

  def queue(conn, %{"id" => id}) do
    post = Social.get!(id)

    case Social.put_ready(post, Post.chosen(post), %{}, reviewer(conn)) do
      {:ok, post} -> conn |> put_flash(:info, done_message("queue", post)) |> back()
      {:error, _} -> conn |> put_flash(:error, "Ce post n'est plus un brouillon.") |> back()
    end
  end

  def publish_now(conn, %{"id" => id}) do
    case Social.publish_now(Social.get!(id), reviewer(conn)) do
      {:ok, post} ->
        conn |> put_flash(:info, done_message("now", post)) |> back()

      {:error, message} when is_binary(message) ->
        conn |> put_flash(:error, message) |> back()

      {:error, _} ->
        conn |> put_flash(:error, "Ce post ne peut pas partir maintenant.") |> back()
    end
  end

  def withdraw(conn, %{"id" => id}) do
    case Social.withdraw(Social.get!(id), reviewer(conn)) do
      {:ok, _} ->
        conn |> put_flash(:info, "Retiré de Buffer : le post est de nouveau en file.") |> back()

      {:error, message} when is_binary(message) ->
        conn |> put_flash(:error, message) |> back()

      {:error, _} ->
        conn |> put_flash(:error, "Ce post n'est pas (ou plus) dans la file Buffer.") |> back()
    end
  end

  def resend(conn, %{"id" => id, "reseau" => network}) do
    case Social.resend(Social.get!(id), network) do
      {:ok, _} -> conn |> put_flash(:info, "Nouvel envoi lancé.") |> back()
      {:error, _} -> conn |> put_flash(:error, "Rien à renvoyer sur ce réseau.") |> back()
    end
  end

  def reject(conn, %{"id" => id}) do
    case Social.reject(Social.get!(id), reviewer(conn)) do
      {:ok, _} -> conn |> put_flash(:info, "Post rejeté.") |> back()
      {:error, _} -> conn |> put_flash(:error, "Ce post n'est plus un brouillon.") |> back()
    end
  end

  def sync(conn, _params) do
    case Social.sync() do
      {:ok, _} -> conn |> put_flash(:info, "Synchronisé avec Buffer.") |> back()
      {:error, message} -> conn |> put_flash(:error, message) |> back()
    end
  end

  # ---------------------------------------------------------------------------

  defp done_message("queue", _post),
    do: "Ajouté à la file, sans date : rien n'est envoyé à Buffer avant « Programmer »."

  defp done_message("draft", _post), do: "Envoyé à valider."
  defp done_message("save", _post), do: "Textes enregistrés."

  defp done_message(action, _post) when action in ["schedule", "now"] do
    cond do
      SyliAtlas.Social.Publisher.simulated?() ->
        "Post validé (simulé : rien n'est envoyé hors production)."

      action == "now" ->
        "Publication immédiate demandée à Buffer."

      true ->
        "Post validé : il part dans la file Buffer."
    end
  end

  defp done_message(_, _post), do: "Enregistré."

  defp networks(params) do
    case params["reseaux"] do
      list when is_list(list) -> Enum.filter(list, &(&1 in Post.networks()))
      "x" -> ["x"]
      "linkedin" -> ["linkedin"]
      _ -> []
    end
  end

  defp texts(params, attrs) do
    post = params["post"] || %{}

    %{
      text_x: blank(post["text_x"]) || attrs.text_x,
      text_linkedin: blank(post["text_linkedin"]) || attrs.text_linkedin
    }
  end

  defp blank(v) when v in [nil, ""], do: nil
  defp blank(v), do: v

  defp reviewer(conn) do
    case conn.assigns[:current_user] do
      %{email: email} -> email
      _ -> "admin"
    end
  end

  defp errors(%Ecto.Changeset{} = cs) do
    cs
    |> Ecto.Changeset.traverse_errors(fn {msg, _} -> msg end)
    |> Enum.map_join(", ", fn {field, msgs} -> "#{label(field)} : #{Enum.join(msgs, ", ")}" end)
  end

  defp label(:text_x), do: "Texte X"
  defp label(:text_linkedin), do: "Texte LinkedIn"
  defp label(field), do: to_string(field)

  defp back(conn), do: redirect(conn, to: ~p"/admin/reseaux")
end
