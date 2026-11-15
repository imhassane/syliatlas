defmodule SyliAtlasWeb.CommunityHTML do
  use SyliAtlasWeb, :html

  alias SyliAtlasWeb.{NationalComponents, ProfileComponents}

  embed_templates "community_html/*"

  def status_class(:met), do: "pill-ok"
  def status_class(:missed), do: "pill-warn"
  def status_class(_), do: "pill-neutral"

  def status_mark(:met), do: "✓"
  def status_mark(:missed), do: "✗"
  def status_mark(_), do: "—"

  @doc "A member's official GDP of the year, else its latest (or nil)."
  def member_national(doc, code, year) do
    entry = SyliAtlas.National.for_country(doc, code)

    SyliAtlas.National.figure(entry, "gdp_usd_bn", year) ||
      SyliAtlas.National.latest(entry, "gdp_usd_bn")
  end
end
