defmodule SyliAtlasWeb.OgImageTest do
  use SyliAtlasWeb.ConnCase, async: false

  alias SyliAtlasWeb.{OgImage, OgImageController}
  alias SyliAtlasWeb.OgImage.Specs

  @png <<137, 80, 78, 71, 13, 10, 26, 10>>

  setup do
    SyliAtlas.Fixtures.load_snapshot!()
    dir = Path.join(System.tmp_dir!(), "syli-og-test-#{System.unique_integer([:positive])}")
    Application.put_env(:syli_atlas, OgImageController, cache_dir: dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  defp og_url(html) do
    [_, url] = Regex.run(~r/<meta property="og:image" content="([^"]+)"/, html)
    URI.parse(url).path
  end

  test "every public page names its share image, in the page's address", %{conn: conn} do
    html = conn |> get("/fr/pays/senegal") |> html_response(200)
    path = og_url(html)
    assert path =~ ~r{^/og/[^/]+/fr/pays/senegal\.png$}
    assert html =~ ~s(<meta property="og:image:width" content="1200">)
    assert html =~ ~s(<meta name="twitter:image")
    assert html =~ ~s(<meta property="og:url" content="http://localhost:4000/fr/pays/senegal">)
    assert html =~ ~s(<meta property="og:locale" content="fr_FR">)
  end

  test "the image is a PNG, kept a year under the current version", %{conn: conn, dir: dir} do
    path = og_url(conn |> get("/fr/pays/senegal") |> html_response(200))
    conn = get(build_conn(), path)

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["image/png"]
    assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
    assert binary_part(conn.resp_body, 0, 8) == @png
    # Kept on disk: the next request reads the file.
    assert [_] = Path.wildcard(Path.join(dir, "**/*.png"))
    assert get(build_conn(), path).resp_body == conn.resp_body
  end

  test "an older version still answers, cached briefly and not kept", %{dir: dir} do
    conn = get(build_conn(), "/og/old-version/fr/pays/kenya.png")
    assert conn.status == 200
    assert get_resp_header(conn, "cache-control") == ["public, max-age=300"]
    assert Path.wildcard(Path.join(dir, "**/*.png")) == []
  end

  test "an address that is not a public page is a 404" do
    assert get(build_conn(), "/og/v/fr/pays/atlantide.png").status == 404
    assert get(build_conn(), "/og/v/fr/pays/senegal").status == 404
    assert get(build_conn(), "/og/v/admin.png").status == 404
    assert get(build_conn(), "/og/v/fr/../admin.png").status == 404
  end

  test "each kind of page has its layout, drawn from its own figures" do
    assert %{layout: :figure, title: "Sénégal", figure: figure} =
             Specs.for_path("/fr/pays/senegal")

    assert figure =~ "%"
    assert %{layout: :figure} = Specs.for_path("/fr/pays/senegal/finances-et-dette")
    assert %{layout: :rating, figure: "CC"} = Specs.for_path("/fr/notations/senegal")
    assert %{layout: :bars, rows: [{_, _, _} | _]} = Specs.for_path("/fr/classement/pib")
    assert %{layout: :bars} = Specs.for_path("/en/debt")
    assert %{layout: :totals, title: "CEDEAO"} = Specs.for_path("/fr/communautes/cedeao")

    assert %{layout: :pair, title: title} = Specs.for_path("/fr/comparer/senegal/cote-d-ivoire")
    assert title =~ "Sénégal ou Côte d'Ivoire"

    assert %{layout: :text} = Specs.for_path("/fr/methode")
    assert Specs.for_path("/fr/pays/atlantide") == nil
    assert Specs.for_path("/api/v1/areas") == nil
  end

  test "French and English images speak their page's language" do
    assert Specs.for_path("/fr/pays/kenya").caption =~ "croissance"
    assert Specs.for_path("/en/countries/kenya").caption =~ "growth"
  end

  test "every layout renders to a PNG; text is escaped" do
    for path <-
          ~w(/fr/pays/senegal /fr/notations/senegal /fr/classement /fr/communautes/cedeao
                   /fr/comparer/senegal/cote-d-ivoire /fr/methode /en/countries/sao-tome-and-principe) do
      spec = Specs.for_path(path)
      assert {:ok, @png <> _} = OgImage.render(spec), path
    end

    svg = OgImage.svg(%{layout: :text, title: "A < B & C", text: "x"})
    assert svg =~ "A &lt; B &amp; C"
  end

  test "the warm-up draws the main pages and removes older versions", %{dir: dir} do
    File.mkdir_p!(Path.join(dir, "older"))
    File.write!(Path.join([dir, "older", "x.png"]), "old")

    paths = SyliAtlas.Workers.OgWarmWorker.paths()
    assert "/fr/pays/senegal" in paths and "/en/ranking/gdp" in paths

    :ok = OgImageController.prune()
    refute File.exists?(Path.join(dir, "older"))
    assert {:ok, @png <> _} = OgImageController.image("/fr/pays/senegal")
  end
end
