defmodule SyliAtlasWeb.Admin.MembersHTML do
  use SyliAtlasWeb, :html

  embed_templates "members_html/*"

  def date(nil), do: "—"
  def date(at), do: Calendar.strftime(at, "%d/%m/%Y")
end
