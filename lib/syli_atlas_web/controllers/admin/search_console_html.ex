defmodule SyliAtlasWeb.Admin.SearchConsoleHTML do
  use SyliAtlasWeb, :html

  import SyliAtlasWeb.AdminComponents, only: [admin_shell: 1]

  embed_templates "search_console_html/*"

  def n(nil), do: "—"
  def n(v) when is_integer(v), do: SyliAtlasWeb.Format.number(v, 0, "fr")
  def n(v) when is_float(v), do: SyliAtlasWeb.Format.number(v, 1, "fr")

  def ctr(_clicks, 0), do: "—"
  def ctr(clicks, impressions), do: SyliAtlasWeb.Format.number(clicks / impressions * 100, 1, "fr") <> " %"

  def day(%Date{} = d), do: Calendar.strftime(d, "%d/%m")
  def day(_), do: ""

  def lang_name("pt"), do: "Portugais"
  def lang_name("es"), do: "Espagnol"
  def lang_name("ar"), do: "Arabe"
  def lang_name("zh"), do: "Chinois"
  def lang_name("hi"), do: "Hindi"
  def lang_name(l), do: l
end
