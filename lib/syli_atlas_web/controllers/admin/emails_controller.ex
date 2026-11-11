defmodule SyliAtlasWeb.Admin.EmailsController do
  @moduledoc "Admin « E-mails envoyés »: alerts and digests sent, waiting or failed."
  use SyliAtlasWeb, :controller

  alias SyliAtlas.Admin.Emails

  @filters %{"envoyes" => :sent, "echecs" => :failed, "recap" => :digest}

  def index(conn, params) do
    filter = if Map.has_key?(@filters, params["filtre"]), do: params["filtre"], else: "tous"

    render(conn, :index,
      page_title: "Admin · E-mails envoyés",
      filter: filter,
      rows:
        SyliAtlasWeb.Pagination.paginate(
          Emails.list(Map.get(@filters, filter, :all), 1000),
          params["page"]
        ),
      params: Map.take(params, ["filtre"]),
      stats: Emails.stats()
    )
  end
end
