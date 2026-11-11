defmodule SyliAtlasWeb.CommunityHTML do
  use SyliAtlasWeb, :html

  alias SyliAtlasWeb.ProfileComponents

  embed_templates "community_html/*"

  def status_class(:met), do: "pill-ok"
  def status_class(:missed), do: "pill-warn"
  def status_class(_), do: "pill-neutral"

  def status_mark(:met), do: "✓"
  def status_mark(:missed), do: "✗"
  def status_mark(_), do: "—"
end
