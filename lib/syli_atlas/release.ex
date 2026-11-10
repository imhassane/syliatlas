defmodule SyliAtlas.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :syli_atlas

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  @doc """
  Runs at every start of the release (`bin/server`): migrations, reference
  data (areas, sources: idempotent upserts), then the bundled IMF snapshot
  only when no edition is published yet. Later editions come from the
  daily check (Oban).
  """
  def setup do
    migrate()
    # The import broadcasts to the admin; outside the running app, PubSub
    # must be started for it.
    {:ok, _} = Application.ensure_all_started(:phoenix_pubsub)

    {:ok, _} =
      Supervisor.start_link([{Phoenix.PubSub, name: SyliAtlas.PubSub}], strategy: :one_for_one)

    {:ok, _, _} =
      Ecto.Migrator.with_repo(SyliAtlas.Repo, fn _repo ->
        SyliAtlas.Geo.seed_areas!()
        SyliAtlas.Sources.seed_sources!()
        SyliAtlas.Market.seed!()

        if SyliAtlas.Sources.published_edition("imf_weo") == nil do
          {:ok, _status, edition} = SyliAtlas.Imports.import_snapshot!()
          IO.puts("IMF edition #{edition.code} online")
        end

        # Snapshots missing, or of an older format than the code: rebuild them.
        if SyliAtlas.Profiles.Queries.snapshot_format("home:fr") !=
             SyliAtlas.Profiles.HomeSnapshot.format() or
             SyliAtlas.Profiles.Queries.snapshot_format("regions:fr") !=
               SyliAtlas.Profiles.RegionsSnapshot.format() do
          SyliAtlas.Profiles.Queries.refresh_snapshots!()
        end

        # Market documents of an older format than the code: rebuild them.
        if SyliAtlas.Market.overview() == nil or
             SyliAtlas.Market.overview()["format"] != SyliAtlas.Market.Snapshots.format() do
          SyliAtlas.Market.Snapshots.rebuild!()
        end

        # First start with a market source configured: import now rather
        # than wait for the evening run (the job waits in the database).
        mansa? = SyliAtlas.Market.Sources.Mansa.configured?()

        IO.puts(
          "market: Mansa key #{if mansa?, do: "found", else: "MISSING (stock_exchange_api_key)"}"
        )

        if mansa? and SyliAtlas.Market.overview()["as_of"] == nil do
          IO.puts("market: no close imported yet, first import queued")
          SyliAtlas.Workers.MarketImportWorker.new(%{}) |> SyliAtlas.Repo.insert!()
        end
      end)

    :ok
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
