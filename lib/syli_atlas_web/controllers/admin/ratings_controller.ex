defmodule SyliAtlasWeb.Admin.RatingsController do
  @moduledoc "Admin: the ratings validation queue, entry by hand and the rows to check."
  use SyliAtlasWeb, :controller

  alias SyliAtlas.Ratings
  alias SyliAtlas.Ratings.{Rating, Review}
  alias SyliAtlasWeb.Admin.RatingsHTML

  def root(conn, _params), do: redirect(conn, to: ~p"/admin/notations")

  def index(conn, params) do
    doc = Ratings.document()
    pending = Review.list("pending", 1000)

    filter =
      if params["filtre"] in ~w(changements confirmations), do: params["filtre"], else: "toutes"

    shown =
      case filter do
        "changements" -> Enum.filter(pending, &(RatingsHTML.kind(&1, doc) == :change))
        "confirmations" -> Enum.filter(pending, &(RatingsHTML.kind(&1, doc) == :confirmation))
        "toutes" -> pending
      end

    render(conn, :index,
      page_title: "Admin · Notations",
      pending: pending,
      shown: SyliAtlasWeb.Pagination.paginate(shown, params["page"]),
      params: Map.take(params, ["filtre", "page", "verif", "decisions"]),
      filter: filter,
      decided:
        (Review.list("approved", 500) ++ Review.list("rejected", 500))
        |> Enum.sort_by(& &1.reviewed_at, {:desc, DateTime})
        |> SyliAtlasWeb.Pagination.paginate(params["decisions"]),
      to_check: Review.to_check(),
      to_check_page: SyliAtlasWeb.Pagination.paginate(Review.to_check(), params["verif"]),
      doc: doc,
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
