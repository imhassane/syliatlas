defmodule SyliAtlasWeb.CompareHTML do
  use SyliAtlasWeb, :html
  alias SyliAtlasWeb.Charts
  embed_templates "compare_html/*"

  def without(slugs, slug), do: List.delete(slugs, slug)
end
