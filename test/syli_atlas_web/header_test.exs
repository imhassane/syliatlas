defmodule SyliAtlasWeb.HeaderTest do
  @moduledoc "The computer header fits one line: short language code, no install button."
  use SyliAtlasWeb.ConnCase, async: false

  setup do
    SyliAtlas.Fixtures.load_snapshot!()
    :ok
  end

  for path <- ["/fr/pays/senegal", "/es/paises/senegal"] do
    test "header of #{path}" do
      html = get(build_conn(), unquote(path)) |> html_response(200)

      [header] =
        html |> LazyHTML.from_document() |> LazyHTML.query(".site-header") |> Enum.take(1)

      # The language as its code; its name stays in the menu and the tooltip.
      [code] = header |> LazyHTML.query("#lang-header summary span") |> Enum.map(&LazyHTML.text/1)
      assert code == unquote(path) |> String.slice(1, 2) |> String.upcase()

      # Install offer: in the drawer and on the home page, not in the header.
      assert LazyHTML.query(header, "[data-install]") |> Enum.count() == 0
      assert LazyHTML.query(header, "a.search-toggle") |> Enum.count() == 1
    end
  end
end
