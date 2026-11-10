defmodule SyliAtlasWeb.Admin.RatingsController do
  @moduledoc "Admin: the ratings validation queue, entry by hand and the rows to check."
  use SyliAtlasWeb, :controller

  alias SyliAtlas.Ratings
  alias SyliAtlas.Ratings.{Rating, Review}

  def root(conn, _params), do: redirect(conn, to: ~p"/admin/notations")

  def index(conn, _params) do
    render(conn, :index,
      page_title: "Admin · Notations",
      pending: Review.list("pending"),
      decided: Review.list("approved", 10) ++ Review.list("rejected", 10),
      to_check: Review.to_check(),
      doc: Ratings.document(),
      extractor?: SyliAtlas.Ratings.Extractor.configured?(),
      last_watch: SyliAtlas.Ratings.Watch.last_run()
    )
  end

  def create(conn, %{"p" => attrs}) do
    case Review.propose(Map.put(attrs, "origin", "manual")) do
      {:ok, _} -> conn |> put_flash(:info, "Proposition ajoutée à la file.") |> back()
      {:error, cs} -> conn |> put_flash(:error, "Proposition refusée : " <> errors(cs)) |> back()
    end
  end

  def approve(conn, %{"id" => id, "p" => attrs}) do
    case Review.approve(Review.get!(id), attrs) do
      {:ok, _} ->
        conn |> put_flash(:info, "Note publiée.") |> back()

      {:error, :missing_source} ->
        conn
        |> put_flash(:error, "Lien vers le communiqué de l'agence obligatoire (https).")
        |> back()

      {:error, :not_agency_source} ->
        conn
        |> put_flash(:error, "La source doit être le communiqué, sur le site de l'agence.")
        |> back()

      {:error, :already_reviewed} ->
        conn |> put_flash(:error, "Déjà traitée.") |> back()

      {:error, %Ecto.Changeset{} = cs} ->
        conn |> put_flash(:error, errors(cs)) |> back()
    end
  end

  def reject(conn, %{"id" => id}) do
    case Review.reject(Review.get!(id)) do
      {:ok, _} -> conn |> put_flash(:info, "Proposition rejetée.") |> back()
      _ -> conn |> put_flash(:error, "Déjà traitée.") |> back()
    end
  end

  def check(conn, %{"id" => id, "r" => attrs}) do
    case Review.mark_checked(SyliAtlas.Repo.get!(Rating, id), attrs) do
      {:ok, _} ->
        conn |> put_flash(:info, "Note vérifiée.") |> back()

      {:error, reason} when reason in [:missing_source, :not_agency_source] ->
        conn
        |> put_flash(:error, "Lien vers le communiqué, sur le site de l'agence, obligatoire.")
        |> back()

      {:error, cs} ->
        conn |> put_flash(:error, errors(cs)) |> back()
    end
  end

  def watch(conn, _params) do
    {:ok, _} = %{} |> SyliAtlas.Workers.RatingsWatchWorker.new() |> Oban.insert()

    conn
    |> put_flash(:info, "Veille lancée : les propositions arrivent dans quelques minutes.")
    |> back()
  end

  defp back(conn), do: redirect(conn, to: ~p"/admin/notations")

  defp errors(%Ecto.Changeset{} = cs) do
    cs
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc -> String.replace(acc, "%{#{k}}", to_string(v)) end)
    end)
    |> Enum.map_join(", ", fn {field, msgs} -> "#{field} #{Enum.join(msgs, ", ")}" end)
  end
end
