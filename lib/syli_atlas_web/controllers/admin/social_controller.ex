defmodule SyliAtlasWeb.Admin.SocialController do
  @moduledoc """
  Admin « Réseaux »: the posts for X and LinkedIn prepared from the site's
  events, to edit, approve (both networks or one) or reject; then the
  history. Nothing leaves without approval.
  """
  use SyliAtlasWeb, :controller

  alias SyliAtlas.Social

  def index(conn, _params) do
    render(conn, :index,
      page_title: "Admin · Réseaux",
      drafts: Social.drafts(),
      history: Social.history(50),
      stats: Social.stats(),
      channels: Social.channels(),
      candidates: SyliAtlas.Social.Drafts.rating_candidates()
    )
  end

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

  def update(conn, %{"id" => id, "post" => attrs}) do
    case Social.update_texts(Social.get!(id), attrs) do
      {:ok, _} -> conn |> put_flash(:info, "Textes enregistrés.") |> back()
      {:error, %Ecto.Changeset{} = cs} -> conn |> put_flash(:error, errors(cs)) |> back()
      {:error, _} -> conn |> put_flash(:error, "Ce post n'est plus un brouillon.") |> back()
    end
  end

  def approve(conn, %{"id" => id} = params) do
    networks =
      case params["reseaux"] do
        "x" -> ["x"]
        "linkedin" -> ["linkedin"]
        _ -> ["x", "linkedin"]
      end

    case Social.approve(Social.get!(id), networks, params["post"] || %{}, reviewer(conn)) do
      {:ok, _} ->
        message =
          if Social.stats().simulated,
            do: "Post validé (simulé : rien n'est envoyé hors production).",
            else: "Post validé : il part dans la file Buffer."

        conn |> put_flash(:info, message) |> back()

      {:error, %Ecto.Changeset{} = cs} ->
        conn |> put_flash(:error, errors(cs)) |> back()

      {:error, _} ->
        conn |> put_flash(:error, "Ce post n'est plus un brouillon.") |> back()
    end
  end

  def reject(conn, %{"id" => id}) do
    case Social.reject(Social.get!(id), reviewer(conn)) do
      {:ok, _} -> conn |> put_flash(:info, "Post rejeté.") |> back()
      {:error, _} -> conn |> put_flash(:error, "Ce post n'est plus un brouillon.") |> back()
    end
  end

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
