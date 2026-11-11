defmodule SyliAtlasWeb.Admin.MarketController do
  @moduledoc """
  Admin « Données de marché » (mockup AdminSources): anomalies to decide,
  the source published per exchange, sources and licences, sources in test.
  """
  use SyliAtlasWeb, :controller

  alias SyliAtlas.Admin.{Jobs, MarketAdmin}
  alias SyliAtlas.Market
  alias SyliAtlas.Market.Catalog

  @tabs ~w(anomalies bourses sources fantome)
  @severities ~w(high mid low)

  def index(conn, params) do
    tab = if params["onglet"] in @tabs, do: params["onglet"], else: "anomalies"
    severity = if params["gravite"] in @severities, do: params["gravite"]
    exchanges = MarketAdmin.exchanges()

    render(conn, :index,
      page_title: "Admin · Données de marché",
      tab: tab,
      severity: severity,
      issues: MarketAdmin.issues(severity),
      counts: MarketAdmin.issue_counts(),
      exchanges: exchanges,
      official: MarketAdmin.official_count(exchanges),
      last_import: MarketAdmin.last_import(),
      quota: MarketAdmin.quota("mansa"),
      sources: Catalog.all(),
      shadow: MarketAdmin.shadow_sources(),
      public?: Market.public?(),
      configured?: mansa_configured?(),
      paused?: MarketAdmin.market_paused?()
    )
  end

  def import(conn, _params) do
    {:ok, _} = SyliAtlas.Workers.MarketImportWorker.new(%{}) |> Oban.insert()

    conn
    |> put_flash(:info, "Import lancé : environ 28 appels, puis contrôles et publication.")
    |> redirect(to: ~p"/admin/marches")
  end

  def pause(conn, %{"paused" => paused}) do
    case Jobs.set_paused("market", paused == "true") do
      :ok ->
        msg =
          if paused == "true",
            do: "Imports de marché en pause.",
            else: "Imports de marché relancés."

        conn |> put_flash(:info, msg) |> redirect(to: ~p"/admin/marches")

      _ ->
        conn
        |> put_flash(:error, "La file des imports ne tourne pas sur ce serveur.")
        |> redirect(to: ~p"/admin/marches")
    end
  end

  def decide(conn, %{"id" => id, "action" => action} = params) do
    back =
      ~p"/admin/marches" <>
        if(params["gravite"] in @severities, do: "?gravite=#{params["gravite"]}", else: "")

    case MarketAdmin.decide(MarketAdmin.get_issue!(id), action) do
      {:ok, :queued} ->
        conn |> put_flash(:info, "Import de rattrapage lancé.") |> redirect(to: back)

      {:ok, _} ->
        conn
        |> put_flash(:info, "Décision enregistrée : les pages bourses sont recalculées.")
        |> redirect(to: back)

      {:error, _} ->
        conn |> put_flash(:error, "Déjà traitée.") |> redirect(to: back)
    end
  end

  defp mansa_configured? do
    mod = Market.Source.module("mansa")

    if Code.ensure_loaded?(mod) and function_exported?(mod, :configured?, 0),
      do: mod.configured?(),
      else: true
  end
end
