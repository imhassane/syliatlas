defmodule SyliAtlasWeb.Api.InternalController do
  @moduledoc """
  What the site itself calls, under `/api/internal`: search suggestions,
  the version check of the service worker, the pages to save offline.
  Not part of the public API: these answers may change with the site.
  """
  use SyliAtlasWeb, :controller

  alias SyliAtlas.{Profiles, Sources}
  alias SyliAtlas.Profiles.Queries
  alias SyliAtlasWeb.Api.Params

  @doc """
  Site search: grouped results and, when the query names a country and a
  theme (« dette sénégal »), the figure itself. Same engine as the search
  page (`SyliAtlasWeb.Search`), used by the suggestions under the field.
  """
  def search(conn, params) do
    locale = Params.locale(params)
    Gettext.put_locale(SyliAtlasWeb.Gettext, locale)
    json(conn, SyliAtlasWeb.Search.run(params["q"] || "", locale))
  end

  def version(conn, _params) do
    edition = Sources.published_edition("imf_weo")

    conn
    |> put_resp_header("cache-control", "no-cache")
    |> json(%{
      version: Profiles.data_version(),
      build: SyliAtlasWeb.Build.id(),
      page_version: SyliAtlasWeb.Build.version(),
      edition:
        edition &&
          %{
            source: "imf_weo",
            id: edition.code,
            label: edition.label,
            published_at: edition.published_at
          }
    })
  end

  @doc "Paths of the pages to save for offline reading, in one language."
  def offline_pages(conn, params) do
    json(conn, %{pages: SyliAtlasWeb.OfflinePages.list(Params.locale(params))})
  end

  def offline_pack(conn, _params) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Queries.offline_pack() || "null")
  end
end
