defmodule SyliAtlasWeb.NotFoundError do
  @moduledoc "Raised when a page slug matches no area; rendered as a 404."
  defexception message: "not found", plug_status: 404
end
