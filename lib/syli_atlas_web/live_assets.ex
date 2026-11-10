defmodule SyliAtlasWeb.LiveAssets do
  @moduledoc """
  Marks a page as needing the LiveView client (`assets/js/live.js`).

  Every LiveView gets this mark through `use SyliAtlasWeb, :live_view`, and
  the root layout then loads `live.js` after `app.js`. Other pages (the
  public ones, cached and without a session) load `app.js` alone, so they
  never download the LiveView client.
  """
  import Phoenix.Component, only: [assign: 3]

  def on_mount(:default, _params, _session, socket), do: {:cont, assign(socket, :live_js, true)}
end
