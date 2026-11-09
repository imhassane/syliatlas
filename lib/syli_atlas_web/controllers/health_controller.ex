defmodule SyliAtlasWeb.HealthController do
  @moduledoc "Health check for the platform (Railway): the database answers."
  use SyliAtlasWeb, :controller

  def show(conn, _params) do
    SyliAtlas.Repo.query!("SELECT 1")
    conn |> put_resp_header("cache-control", "no-store") |> text("ok")
  end
end
