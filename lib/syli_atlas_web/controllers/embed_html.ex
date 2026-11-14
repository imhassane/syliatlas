defmodule SyliAtlasWeb.EmbedHTML do
  @moduledoc "The framed views and the page that writes the code (SyliAtlasWeb.EmbedController)."
  use SyliAtlasWeb, :html

  alias SyliAtlasWeb.Charts

  embed_templates "embed_html/*"

  @doc "The `data-theme` a frame starts with; `auto` follows the reader (embed-frame.js)."
  def start_theme("dark"), do: "dark"
  def start_theme(_), do: "light"
end
