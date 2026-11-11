defmodule SyliAtlasWeb.Admin.UpdatesController do
  @moduledoc """
  Admin « Mises à jour » (mockups AdminMaj and AdminRun): Oban queues and
  jobs, data sources and their editions, the reading functions against the
  1.5 ms budget, and the detail of one import.
  """
  use SyliAtlasWeb, :controller

  alias SyliAtlas.Admin.Jobs
  alias SyliAtlas.{Imports, Sources}
  alias SyliAtlas.Profiles.{Benchmark, QueryStats}
  alias SyliAtlas.Workers.{CheckSourcesWorker, ImportEditionWorker}
  alias SyliAtlasWeb.Pagination

  @tabs ~w(taches sources fonctions)
  @filters %{"echecs" => :failed, "en-cours" => :running}

  def index(conn, params) do
    tab = if params["onglet"] in @tabs, do: params["onglet"], else: "taches"
    filter = if Map.has_key?(@filters, params["filtre"]), do: params["filtre"], else: "toutes"
    stats = QueryStats.summary()

    render(conn, :index,
      page_title: "Admin · Mises à jour",
      tab: tab,
      filter: filter,
      queues: Jobs.queues(),
      jobs:
        Pagination.from_count(
          Jobs.count(Map.get(@filters, filter, :all)),
          params["page"],
          &Jobs.recent(Map.get(@filters, filter, :all), &1, &2)
        ),
      params: Map.take(params, ["onglet", "filtre"]),
      failures: Jobs.failures(7),
      sources: Sources.list_sources(),
      editions: Pagination.paginate(Sources.list_editions(500), params["page"]),
      online: Sources.published_edition("imf_weo"),
      imf: Sources.get_source("imf_weo"),
      fns: stats,
      budget_us: QueryStats.budget_us()
    )
  end

  def check(conn, _params) do
    {:ok, _} = CheckSourcesWorker.new(%{}) |> Oban.insert()

    conn
    |> put_flash(:info, "Vérification lancée : le FMI est interrogé dans quelques secondes.")
    |> redirect(to: ~p"/admin/mises-a-jour")
  end

  def pause(conn, %{"queue" => queue, "paused" => paused}) do
    case Jobs.set_paused(queue, paused == "true") do
      :ok ->
        msg =
          if paused == "true",
            do: "File « #{queue} » en pause.",
            else: "File « #{queue} » relancée."

        conn |> put_flash(:info, msg) |> redirect(to: ~p"/admin/mises-a-jour")

      _ ->
        conn
        |> put_flash(:error, "La file « #{queue} » ne tourne pas sur ce serveur.")
        |> redirect(to: ~p"/admin/mises-a-jour")
    end
  end

  def measure(conn, _params) do
    QueryStats.reset()
    Benchmark.run(200)

    conn
    |> put_flash(:info, "Lectures mesurées : chaque fonction rejouée 200 fois.")
    |> redirect(to: ~p"/admin/mises-a-jour?onglet=fonctions")
  end

  def retry_job(conn, %{"id" => id} = params) do
    Oban.retry_job(String.to_integer(id))
    back = params["retour"] || ~p"/admin/mises-a-jour"
    back = if String.starts_with?(back, "/admin/"), do: back, else: ~p"/admin/mises-a-jour"
    conn |> put_flash(:info, "Tâche relancée.") |> redirect(to: back)
  end

  def edition(conn, %{"id" => id} = params) do
    edition = Sources.get_edition!(id)
    previous = Sources.previous_edition(edition)
    all? = params["ecarts"] == "tout"

    render(conn, :edition,
      page_title: "Admin · " <> edition.label,
      edition: edition,
      previous: previous,
      all?: all?,
      revisions:
        Pagination.paginate(
          if(previous,
            do: Sources.revisions(edition, previous, if(all?, do: 0.05, else: 1.0), 5000),
            else: []
          ),
          params["page"]
        ),
      params: Map.take(params, ["ecarts"]),
      after_job: Jobs.latest("SyliAtlas.Workers.AfterPublishWorker", %{edition_id: edition.id}),
      names: SyliAtlas.Geo.list_areas() |> Map.new(&{&1.code, &1.name_fr})
    )
  end

  def rerun(conn, %{"id" => id}) do
    edition = Sources.get_edition!(id)
    {:ok, _} = ImportEditionWorker.new(%{label: edition.label, force: true}) |> Oban.insert()

    conn
    |> put_flash(:info, "Import relancé : l'édition est téléchargée de nouveau.")
    |> redirect(to: ~p"/admin/mises-a-jour/editions/#{id}")
  end

  def restore(conn, %{"id" => id}) do
    case Imports.restore!(Sources.get_edition!(id)) do
      {:ok, edition, _} ->
        conn
        |> put_flash(:info, "« #{edition.label} » est de nouveau en ligne.")
        |> redirect(to: ~p"/admin/mises-a-jour/editions/#{id}")

      {:error, _} ->
        conn
        |> put_flash(:error, "Cette édition ne peut pas être remise en ligne.")
        |> redirect(to: ~p"/admin/mises-a-jour/editions/#{id}")
    end
  end
end
