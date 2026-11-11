defmodule SyliAtlasWeb.Admin.SearchMissesController do
  @moduledoc "Admin: searches that found nothing, to add the missing names to the index."
  use SyliAtlasWeb, :controller

  def index(conn, params) do
    render(conn, :index,
      page_title: "Admin · Recherches sans résultat",
      misses: SyliAtlasWeb.Pagination.paginate(SyliAtlas.Search.Miss.top(1000), params["page"])
    )
  end
end
