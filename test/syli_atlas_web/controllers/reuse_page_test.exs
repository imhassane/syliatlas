defmodule SyliAtlasWeb.ReusePageTest do
  @moduledoc "The page for journalists: licence, citation, downloads, embed."
  use SyliAtlasWeb.ConnCase, async: false

  setup do
    SyliAtlas.Fixtures.load_snapshot!()
    :ok
  end

  test "the reuse page in French and English, linked from the footer and the sitemap" do
    fr = build_conn() |> get("/fr/reutiliser") |> html_response(200) |> LazyHTML.from_document()
    assert fr |> LazyHTML.query("#reuse-citation") |> LazyHTML.text() =~ "CC BY 4.0"
    assert fr |> LazyHTML.query("#reuse-terms tbody tr") |> Enum.count() == 4
    downloads = fr |> LazyHTML.query(~s(#reuse-steps a[href*="/fr/pays/senegal/donnees"]))
    assert Enum.count(downloads) == 3
    assert fr |> LazyHTML.query("#footer-reuse") |> Enum.count() == 1

    assert build_conn() |> get("/en/reuse") |> html_response(200) =~ "CC BY 4.0"
    assert build_conn() |> get("/sitemaps/pages.xml") |> response(200) =~ "/fr/reutiliser"
  end
end
