defmodule SyliAtlasWeb.SimulatorPagesTest do
  use SyliAtlasWeb.ConnCase, async: false
  alias SyliAtlas.MarketFixtures, as: F
  alias SyliAtlasWeb.SimulatorController

  setup do
    SyliAtlas.Fixtures.load_snapshot!()
    F.import!()
    :ok
  end

  defp doc(conn, path), do: conn |> get(path) |> html_response(200) |> LazyHTML.from_document()
  defp text(html, sel), do: html |> LazyHTML.query(sel) |> LazyHTML.text() |> String.trim()
  defp count(html, sel), do: html |> LazyHTML.query(sel) |> Enum.count()

  test "before the history is imported the page says the figures are on their way", %{conn: conn} do
    html = doc(conn, "/fr/bourses/simulateur")
    assert count(html, "#simulator-empty") == 1
    assert count(html, "#simulator-form, #simulator-result") == 0
  end

  describe "with an index history" do
    setup do
      F.import_history!()
      :ok
    end

    test "the BRVM in euros by default, with the result, the chart and the years", %{conn: conn} do
      html = doc(conn, "/fr/bourses/simulateur")
      assert count(html, "h1") == 1
      assert count(html, "#simulator-form") == 1
      assert count(html, ~s(#sim-index option[value="brvm"][selected])) == 1
      assert count(html, ~s(#sim-currency option[value="EUR"][selected])) == 1
      assert text(html, "#sim-final") =~ "€"
      assert count(html, "#simulator-chart svg") == 1
      assert count(html, "#simulator-years tbody tr") >= 3
      assert count(html, "#sim-entry li") >= 1
      # The euro is tied to the CFA franc: no exchange rate effect to show.
      refute text(html, "#simulator-stats") =~ "pts"
      assert count(html, "#sim-fx-missing") == 0
      assert html |> LazyHTML.query("#simulator-source") |> LazyHTML.text() =~ "MansaAPI"
    end

    test "the settings are read from the address, and the page is then not indexed", %{
      conn: conn
    } do
      conn =
        get(conn, "/fr/bourses/simulateur?indice=brvm&depuis=2020-01-01&montant=500&devise=XOF")

      html = conn |> html_response(200) |> LazyHTML.from_document()
      assert text(html, "#sim-final") =~ "XOF"

      assert html
             |> LazyHTML.query(~s(meta[name="robots"]))
             |> LazyHTML.attribute("content")
             |> hd() =~ "noindex"

      assert text(html, "#simulator-chart h2") =~ "500"
      assert text(html, "#simulator-chart h2") =~ "janvier 2020"

      share = html |> LazyHTML.query(".sim-share-url") |> LazyHTML.attribute("value") |> hd()
      assert share =~ "depuis=2020-01-01" and share =~ "montant=500"
      wa = html |> LazyHTML.query("#sim-whatsapp") |> LazyHTML.attribute("href") |> hd()
      assert wa =~ "https://wa.me/?text="
    end

    test "without a rate for the start day the result stays in the index currency", %{
      conn: conn
    } do
      html = doc(conn, "/fr/bourses/simulateur?indice=brvm&depuis=2020-01-01&devise=USD")
      assert count(html, "#sim-fx-missing") == 1
      assert text(html, "#sim-final") =~ "XOF"
    end

    test "the page without settings is indexed, with its structured data", %{conn: conn} do
      html = doc(conn, "/en/stock-exchanges/simulator")
      robots = html |> LazyHTML.query(~s(meta[name="robots"])) |> LazyHTML.attribute("content")
      refute Enum.any?(robots, &(&1 =~ "noindex"))

      types =
        html
        |> LazyHTML.query(~s(script[type="application/ld+json"]))
        |> Enum.flat_map(&List.wrap(Jason.decode!(LazyHTML.text(&1))))
        |> Enum.map(& &1["@type"])

      assert "WebApplication" in types and "BreadcrumbList" in types
    end

    test "the exchange page and the themes menu lead to the simulator", %{conn: conn} do
      html = doc(conn, "/fr/bourses/brvm")
      href = html |> LazyHTML.query("#exchange-simulate") |> LazyHTML.attribute("href") |> hd()
      assert href == "/fr/bourses/simulateur?indice=brvm"
      assert count(html, ~s(.nav-mega a[href="/fr/bourses/simulateur"])) == 1

      # An exchange without three years of closes has no button.
      assert count(doc(conn, "/fr/bourses/ngx"), "#exchange-simulate") == 0
    end
  end

  test "amounts and dates are read leniently, and bounded" do
    assert SimulatorController.parse_amount("1 000,50") == 1000.5
    assert SimulatorController.parse_amount("-5") == nil
    assert SimulatorController.parse_amount("1e20") == nil
    assert SimulatorController.parse_amount("abc") == nil
    assert SimulatorController.parse_date("2020-03-04") == ~D[2020-03-04]
    assert SimulatorController.parse_date("2018") == ~D[2018-01-01]
    assert SimulatorController.parse_date("hier") == nil
  end
end
