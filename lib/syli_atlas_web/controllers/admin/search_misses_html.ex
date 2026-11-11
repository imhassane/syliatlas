defmodule SyliAtlasWeb.Admin.SearchMissesHTML do
  use SyliAtlasWeb, :html

  import SyliAtlasWeb.AdminComponents, only: [admin_shell: 1, admin_pager: 1]

  embed_templates "search_misses_html/*"
end
