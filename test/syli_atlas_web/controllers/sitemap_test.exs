defmodule SyliAtlasWeb.SitemapTest do
  use SyliAtlasWeb.ConnCase, async: false

  setup do
    SyliAtlas.Fixtures.load_snapshot!()
    :ok
  end

  test "the sitemap lists countries and rating pages with their English twin", %{conn: conn} do
    xml = conn |> get("/sitemap.xml") |> response(200)
    assert xml =~ "/fr/pays/cote-d-ivoire</loc>"
    assert xml =~ ~r{hreflang="en" href="http://[^"]+/en/countries/cote-d-ivoire"}
    assert xml =~ "/fr/notations/cote-d-ivoire</loc>"
    refute xml =~ "/admin"
  end

  test "robots.txt points to the sitemap and keeps crawlers out of the admin", %{conn: conn} do
    txt = conn |> get("/robots.txt") |> response(200)
    assert txt =~ "Sitemap: "
    assert txt =~ "Disallow: /admin"
  end
end
