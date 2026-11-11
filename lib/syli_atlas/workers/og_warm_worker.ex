defmodule SyliAtlas.Workers.OgWarmWorker do
  @moduledoc """
  Draws the share images of the main pages ahead of the first share, after
  each deploy, IMF publication and market publication (each changes the
  version in their address), and removes the images of older versions.

  Main pages: home, ranking, debt, ratings, the 54 countries, the regions,
  the communities and the exchanges, in French and English. Other pages
  (tabs, securities, comparisons) are drawn on their first request.
  """
  use Oban.Worker,
    queue: :seo,
    max_attempts: 3,
    unique: [period: 300, states: [:available, :scheduled, :executing]]

  alias SyliAtlasWeb.{OgImageController, Paths}

  @impl Oban.Worker
  def perform(_job) do
    OgImageController.prune()
    Enum.each(paths(), &OgImageController.image/1)
    :ok
  end

  @doc "Queues a run; `delay` seconds lets a publication settle first."
  def enqueue(delay \\ 30), do: new(%{}, schedule_in: delay) |> Oban.insert()

  @doc "The pages whose image is drawn in advance."
  def paths do
    for locale <- ["fr", "en"],
        path <- pages(locale),
        do: path
  end

  defp pages(locale) do
    exchanges =
      with true <- SyliAtlas.Market.public?(),
           %{"exchanges" => xs} <- SyliAtlas.Market.overview() do
        for x <- xs, do: Paths.exchange(locale, x["exchange"]["code"])
      else
        _ -> []
      end

    [Paths.home(locale), Paths.ranking(locale), Paths.debt(locale), Paths.ratings(locale)] ++
      for(
        a <- SyliAtlas.Geo.list_areas(),
        a.kind in ["country", "region", "continent"],
        do: Paths.area(locale, a)
      ) ++
      for(c <- SyliAtlas.Economy.Communities.all(), do: Paths.community(locale, c.slug[locale])) ++
      exchanges
  end
end
