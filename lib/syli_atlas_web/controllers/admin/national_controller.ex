defmodule SyliAtlasWeb.Admin.NationalController do
  @moduledoc """
  Admin: national figures the automatic checks did not let through
  (`SyliAtlas.National.Verify`). They are already shown with the « being
  checked » badge; a person confirms them (they count from then on) or
  rejects them (they leave the public pages).
  """
  use SyliAtlasWeb, :controller

  alias SyliAtlas.National
  alias SyliAtlas.National.Rebasings

  def index(conn, _params) do
    render(conn, :index,
      page_title: "Admin · Chiffres nationaux",
      pending: National.pending(),
      decided: National.decided(50),
      doc: National.document(),
      proposed: Rebasings.proposed(),
      rebasings: Rebasings.published(),
      watch_ran: SyliAtlas.National.Watch.last_run(),
      watch_ready: SyliAtlas.National.RebasingExtractor.configured?()
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

  @doc "A rebasing typed in the admin: published at once."
  def create_rebasing(conn, %{"rebasing" => attrs}) do
    case Rebasings.create(attrs, reviewer(conn)) do
      {:ok, _} -> conn |> put_flash(:info, "Rebasage publié : l'alerte est en ligne.") |> back()
      {:error, cs} -> conn |> put_flash(:error, "Rebasage refusé : #{errors(cs)}") |> back()
    end
  end

  @doc "A proposal of the watch, completed and published."
  def publish_rebasing(conn, %{"id" => id} = params) do
    r = Rebasings.get!(id)

    case Rebasings.publish(r, params["rebasing"] || %{}, reviewer(conn)) do
      {:ok, _} -> conn |> put_flash(:info, "Rebasage publié : l'alerte est en ligne.") |> back()
      {:error, cs} -> conn |> put_flash(:error, "À compléter : #{errors(cs)}") |> back()
    end
  end

  def reject_rebasing(conn, %{"id" => id}) do
    Rebasings.reject!(Rebasings.get!(id), reviewer(conn))
    conn |> put_flash(:info, "Rebasage écarté.") |> back()
  end

  def integrated_rebasing(conn, %{"id" => id}) do
    Rebasings.mark_integrated!(Rebasings.get!(id), reviewer(conn))
    conn |> put_flash(:info, "Alerte close : le FMI a intégré le rebasage.") |> back()
  end

  def watch(conn, _params) do
    {:ok, _} = %{} |> SyliAtlas.Workers.RebasingWatchWorker.new() |> Oban.insert()

    conn
    |> put_flash(:info, "Veille lancée : les propositions arrivent dans quelques minutes.")
    |> back()
  end

  defp errors(%Ecto.Changeset{} = cs) do
    cs
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc -> String.replace(acc, "%{#{k}}", to_string(v)) end)
    end)
    |> Enum.map_join(", ", fn {field, msgs} -> "#{field} #{Enum.join(msgs, ", ")}" end)
  end

  defp reviewer(conn) do
    case conn.assigns[:current_user] do
      %{email: email} -> email
      _ -> "admin"
    end
  end

  defp back(conn), do: redirect(conn, to: ~p"/admin/chiffres-nationaux")
end
