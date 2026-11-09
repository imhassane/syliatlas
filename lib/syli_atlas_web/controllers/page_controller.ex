defmodule SyliAtlasWeb.PageController do
  use SyliAtlasWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
