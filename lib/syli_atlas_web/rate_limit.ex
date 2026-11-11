defmodule SyliAtlasWeb.RateLimit do
  @moduledoc """
  Request counters for the API, in memory (ETS). One instance serves the
  site, so no shared store is needed; counters restart with the app.
  Used by `SyliAtlasWeb.Plugs.ApiRateLimit`.
  """
  use Hammer, backend: :ets
end
