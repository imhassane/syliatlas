defmodule SyliAtlasWeb.MarketPagesTest do
  use SyliAtlasWeb.ConnCase, async: false
  alias SyliAtlas.MarketFixtures, as: F

  setup do
    SyliAtlas.Fixtures.load_snapshot!()
    F.import!()
    :ok
  end

  defp doc(conn, path), do: conn |> get(path) |> html_response(200) |> LazyHTML.from_document()

  test "the list shows every exchange, the header band and the source", %{conn: conn} do
    html = doc(conn, "/fr/bourses")
    assert html |> LazyHTML.query("#market-list tbody tr") |> Enum.count() == 21
    assert html |> LazyHTML.query("#site-ticker .site-ticker-list") |> Enum.count() == 2
    text = LazyHTML.text(html)
    assert text =~ "Data by MansaAPI"
    assert text =~ "pas un conseil en investissement"
    # Missing, old and suspicious indices are shown as such.
    assert html |> LazyHTML.query("#exchange-egx") |> LazyHTML.text() =~ "indice non fourni"
    assert html |> LazyHTML.query("#exchange-mse") |> LazyHTML.text() =~ "ancienne"
    assert html |> LazyHTML.query("#exchange-jse .market-check") |> Enum.count() == 1
  end

  test "the header sums up the session: indices up, down and missing", %{conn: conn} do
    html = doc(conn, "/fr/bourses")
    exchanges = SyliAtlas.Market.overview()["exchanges"]
    given = Enum.filter(exchanges, & &1["index"]["value"])
    up = Enum.count(given, &Decimal.gt?(&1["index"]["change_pct"], 0))
    down = Enum.count(given, &Decimal.lt?(&1["index"]["change_pct"], 0))

    assert up > 0
    assert html |> LazyHTML.query("#summary-up") |> LazyHTML.text() == "▲ #{up}"
    assert html |> LazyHTML.query("#summary-down") |> LazyHTML.text() == "▼ #{down}"

    assert html |> LazyHTML.query("#summary-missing") |> LazyHTML.text() ==
             "#{length(exchanges) - length(given)}"

    assert html |> LazyHTML.query("#market-hero h1") |> LazyHTML.text() == "Bourses africaines"
  end

  test "before any import the header and the table give way to « figures on their way »" do
    SyliAtlas.Repo.delete_all(SyliAtlas.Market.EodPrice)
    SyliAtlas.Repo.delete_all(SyliAtlas.Market.IndexValue)
    SyliAtlas.Market.Snapshots.rebuild!()
    SyliAtlasWeb.Ticker.reset()

    html = doc(build_conn(), "/fr/bourses")
    assert html |> LazyHTML.query("#market-empty") |> Enum.count() == 1
    assert html |> LazyHTML.query("#market-summary, #market-table") |> Enum.count() == 0
    assert html |> LazyHTML.query(~s(#site-ticker a[href^="/fr/bourses"])) |> Enum.count() == 0
  end

  test "the list is searched, filtered and sorted through the URL", %{conn: conn} do
    rows = fn path ->
      doc(conn, path)
      |> LazyHTML.query("#market-list tbody tr")
      |> Enum.map(&LazyHTML.attribute(&1, "id"))
    end

    assert rows.("/fr/bourses?q=cote+d%27ivoire") |> List.flatten() == ["exchange-brvm"]
    assert rows.("/fr/bourses?q=XOF") |> List.flatten() == ["exchange-brvm"]
    assert rows.("/en/stock-exchanges?q=nigeria") |> List.flatten() == ["exchange-ngx"]

    west = rows.("/fr/bourses?region=west_africa") |> List.flatten()
    assert Enum.sort(west) == Enum.sort(~w(exchange-ngx exchange-brvm exchange-gse exchange-bvc))

    by_change = rows.("/fr/bourses?sort=change") |> List.flatten()
    assert hd(by_change) == "exchange-jse"

    assert List.last(rows.("/fr/bourses?sort=change&dir=asc") |> List.flatten()) in ~w(exchange-egx exchange-casablanca exchange-vfex exchange-nsx exchange-bvmac exchange-bvc exchange-use exchange-ese)

    none = doc(conn, "/fr/bourses?q=zzzz")
    assert LazyHTML.query(none, "#market-none") |> Enum.count() == 1
    # A filtered list is not indexed.
    assert conn |> get("/fr/bourses?q=xof") |> html_response(200) =~
             ~s(name="robots" content="noindex)
  end

  test "headers line up with their columns: text left, figures right", %{conn: conn} do
    html = doc(conn, "/fr/bourses")

    heads =
      html
      |> LazyHTML.query("#market-list thead th")
      |> Enum.map(&(LazyHTML.attribute(&1, "class") |> List.first("")))

    first_row =
      html
      |> LazyHTML.query("#market-list tbody tr:first-child > *")
      |> Enum.map(&(LazyHTML.attribute(&1, "class") |> List.first("")))

    assert length(heads) == length(first_row)

    for {h, c} <- Enum.zip(heads, first_row) do
      assert String.contains?(h, "l") == String.contains?(c, "l"), "header #{h} vs cell #{c}"
    end
  end

  test "an exchange page: index, session, movers, securities, sources", %{conn: conn} do
    html = doc(conn, "/fr/bourses/brvm")
    text = LazyHTML.text(html)
    assert text =~ "520,74"
    assert text =~ "+50,6"
    assert html |> LazyHTML.query("#securities-table tbody tr") |> Enum.count() == 5

    assert html |> LazyHTML.query("#security-ecla .market-flag") |> LazyHTML.text() =~
             "à vérifier"

    assert html |> LazyHTML.query("#index-chart-empty") |> Enum.count() == 1
    assert html |> LazyHTML.query(".market-sources li") |> Enum.count() == 1
    # Member countries link to their profiles, from the shared header.
    assert html
           |> LazyHTML.query(~s(.entity-chips a[href="/fr/pays/cote-d-ivoire"]))
           |> Enum.count() == 1
  end

  test "exchange and security pages share the header of the profiles", %{conn: conn} do
    html = doc(conn, "/fr/bourses/brvm")
    assert html |> LazyHTML.query(".exchange-head h1.entity-name") |> LazyHTML.text() =~ "BRVM"
    assert html |> LazyHTML.query(".exchange-head .entity-mark svg") |> Enum.count() == 1
    assert html |> LazyHTML.query("#exchange-kpis li") |> Enum.count() == 4
    assert html |> LazyHTML.query(".entity-actions #follow-alert") |> Enum.count() == 1
    assert html |> LazyHTML.query(".tab-intro [data-answer]") |> Enum.count() == 1

    html = doc(conn, "/fr/bourses/brvm/alpt")
    assert html |> LazyHTML.query(".security-head .entity-tag") |> LazyHTML.text() =~ "ALPT"
    assert html |> LazyHTML.query("#security-kpis li") |> Enum.count() == 6
    assert html |> LazyHTML.query("#kpi-close") |> LazyHTML.text() =~ "XOF"
  end

  test "an exchange's securities are paged by 20", %{conn: conn} do
    html = doc(conn, "/en/stock-exchanges/jse")
    assert html |> LazyHTML.query("#securities-table tbody tr") |> Enum.count() == 20
    html2 = doc(conn, "/en/stock-exchanges/jse?page=13")
    assert html2 |> LazyHTML.query("#securities-table tbody tr") |> Enum.count() == 10
  end

  test "a security page, its canonical URL and its value in dollars", %{conn: conn} do
    html = doc(conn, "/fr/bourses/brvm/alpt")
    text = LazyHTML.text(html)
    assert text =~ "Alpha Télécom Sénégal"
    assert text =~ "4 000 XOF"
    assert text =~ "≈ 6,7 $"
    assert html |> LazyHTML.query("#price-chart-empty") |> Enum.count() == 1
    assert conn |> get("/fr/bourses/brvm/ALPT") |> redirected_to(301) == "/fr/bourses/brvm/alpt"
  end

  test "the funds page", %{conn: conn} do
    html = doc(conn, "/fr/bourses/etf")
    assert html |> LazyHTML.query("#etfs-table tbody tr") |> Enum.count() == 2
    assert html |> LazyHTML.query("#etf-goldx .market-flag") |> LazyHTML.text() =~ "or physique"
  end

  test "the search finds exchanges and securities, by name or ticker", %{conn: _conn} do
    SyliAtlasWeb.Search.Index.reset()
    assert hd(SyliAtlasWeb.Search.run("BRVM", "fr")["results"])["path"] == "/fr/bourses/brvm"
    hit = hd(SyliAtlasWeb.Search.run("ALPT", "fr")["results"])
    assert hit["path"] == "/fr/bourses/brvm/alpt" and hit["type"] == "security"
  end

  test "unknown exchange or security is a 404", %{conn: conn} do
    assert_error_sent 404, fn -> get(conn, "/fr/bourses/nowhere") end
    assert_error_sent 404, fn -> get(build_conn(), "/fr/bourses/brvm/nothing") end
  end

  test "a country page shows its exchange", %{conn: conn} do
    html = doc(conn, "/fr/pays/cote-d-ivoire/marches")
    block = LazyHTML.query(html, "#market")
    assert LazyHTML.text(block) =~ "BRVM"
    assert LazyHTML.text(block) =~ "bourse régionale"
    nigeria = doc(build_conn(), "/en/countries/nigeria/markets")

    assert LazyHTML.query(nigeria, ~s(#market a[href="/en/stock-exchanges/ngx"])) |> Enum.count() ==
             1
  end

  test "the menu links to the exchanges while they are public", %{conn: conn} do
    SyliAtlasWeb.Search.Index.reset()
    html = doc(conn, "/fr")
    assert LazyHTML.query(html, ~s(#header-nav a[href="/fr/bourses"])) |> Enum.count() == 1
    assert LazyHTML.query(html, ~s(.site-footer a[href="/fr/bourses/brvm"])) |> Enum.count() == 1
    assert LazyHTML.text(LazyHTML.query(html, ".footer-credits")) =~ "Data by MansaAPI"
  end

  test "the figures carry the credit the licence asks for, linked to the source", %{
    conn: conn
  } do
    for path <- ["/fr/bourses", "/fr/bourses/brvm", "/fr/bourses/brvm/alpt", "/fr/bourses/etf"] do
      html = doc(build_conn(), path)
      links = LazyHTML.query(html, ~s([data-credit] a[href="https://mansaapi.com"]))
      assert Enum.count(links) >= 1, path
      assert LazyHTML.text(links) =~ "Data by MansaAPI"
    end

    country = doc(conn, "/fr/pays/cote-d-ivoire/marches")

    assert LazyHTML.query(country, ~s(#market [data-credit] a[href="https://mansaapi.com"]))
           |> Enum.count() == 1
  end

  describe "when no active source may be shown and preview is off" do
    setup do
      Application.put_env(:syli_atlas, SyliAtlas.Market, preview: false)
      on_exit(fn -> Application.put_env(:syli_atlas, SyliAtlas.Market, preview: true) end)
    end

    test "the market section is not public" do
      hidden = [%{status: "active", licence: %{display_public: false}}]
      refute SyliAtlas.Market.public?(hidden)
      assert SyliAtlas.Market.public?()
    end

    test "MansaAPI's licence alone makes the pages public", %{conn: conn} do
      assert conn |> get("/fr/bourses") |> html_response(200)
    end
  end
end
