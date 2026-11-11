defmodule SyliAtlasWeb.OfflinePages do
  @moduledoc """
  The pages a visitor's device saves in the background for offline reading:
  the main pages and every country, region and Africa page, in one
  language. The service worker fetches the list from
  `GET /api/internal/offline-pages?locale=fr` and caches each page it lacks.
  The home page is not listed: the service worker saves it when installed.
  """
  use Gettext, backend: SyliAtlasWeb.Gettext

  alias SyliAtlas.Geo
  alias SyliAtlas.Geo.Area
  alias SyliAtlasWeb.Paths

  def list(locale) when locale in ["fr", "en"], do: Enum.map(entries(locale), & &1.path)

  @doc """
  The same pages with their names and kinds (`page`, `continent`, `region`,
  `country`), for the offline page, which shows those already saved.
  """
  def entries(locale) when locale in ["fr", "en"] do
    Gettext.put_locale(SyliAtlasWeb.Gettext, locale)

    main = [
      %{path: Paths.regions(locale), name: gettext("Regions"), kind: "page"},
      %{path: Paths.ranking_main(locale), name: gettext("Ranking"), kind: "page"},
      %{path: Paths.method(locale), name: gettext("Method"), kind: "page"}
    ]

    areas =
      Geo.list_areas()
      |> Enum.sort_by(&{&1.kind != "continent", &1.kind != "region", Area.name(&1, locale)})
      |> Enum.map(&%{path: Paths.area(locale, &1), name: Area.name(&1, locale), kind: &1.kind})

    main ++ areas
  end
end
