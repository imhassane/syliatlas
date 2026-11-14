defmodule SyliAtlasWeb.Admin.NationalController do
  @moduledoc """
  Admin: national figures the automatic checks did not let through
  (`SyliAtlas.National.Verify`). They are already shown with the « being
  checked » badge; a person confirms them (they count from then on) or
  rejects them (they leave the public pages).
  """
  use SyliAtlasWeb, :controller

  alias SyliAtlas.National

  def index(conn, _params) do
    render(conn, :index,
      page_title: "Admin · Chiffres nationaux",
      pending: National.pending(),
      decided: National.decided(50),
      doc: National.document()
    )
  end

  def verify(conn, %{"id" => id}) do
    case National.get!(id) do
      %{status: "pending_review"} = f ->
        National.verify!(f, reviewer(conn))

        conn
        |> put_flash(:info, "Chiffre vérifié : il compte dans la somme et les classements.")
        |> back()

      _ ->
        conn |> put_flash(:error, "Déjà traité.") |> back()
    end
  end

  def reject(conn, %{"id" => id}) do
    case National.get!(id) do
      %{status: status} = f when status in ["pending_review", "auto_verified", "verified"] ->
        National.reject!(f, reviewer(conn))
        conn |> put_flash(:info, "Chiffre retiré des pages publiques.") |> back()

      _ ->
        conn |> put_flash(:error, "Déjà retiré.") |> back()
    end
  end

  defp reviewer(conn) do
    case conn.assigns[:current_user] do
      %{email: email} -> email
      _ -> "admin"
    end
  end

  defp back(conn), do: redirect(conn, to: ~p"/admin/chiffres-nationaux")
end
