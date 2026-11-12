defmodule SyliAtlasWeb.CurrencyPagesTest do
  use SyliAtlasWeb.ConnCase, async: false

  alias SyliAtlas.FxFixtures

  defp doc(conn, path), do: conn |> get(path) |> html_response(200) |> LazyHTML.from_document()
  defp has?(doc, selector), do: LazyHTML.query(doc, selector) |> Enum.count() > 0
  defp text(doc, selector), do: doc |> LazyHTML.query(selector) |> LazyHTML.text()

  describe "before the first import" do
    test "the page says the figures are on their way", %{conn: conn} do
      doc = doc(conn, "/fr/monnaies")
      assert has?(doc, "#currency-empty")
      refute has?(doc, "#currency-list")
    end
  end

  describe "with rates" do
    setup do
      FxFixtures.import!()
      :ok
    end

    test "every African currency, largest rise first, with flags and the source", %{conn: conn} do
      doc = doc(conn, "/fr/monnaies")
      rows = LazyHTML.query(doc, "#currency-list tbody tr")
      assert Enum.count(rows) == length(SyliAtlas.Economy.Currencies.codes())

      # Only the currencies the fixture knows have a change; the naira leads.
      first = rows |> Enum.at(0) |> LazyHTML.text()
      assert first =~ "Naira" or first =~ "Rand"
      assert text(doc, "#currency-NGN") =~ "1 346"
      assert text(doc, "#currency-NGN") =~ "+6,6 %"
      assert text(doc, "#currency-XOF") =~ "−3,4 %"
      assert has?(doc, "#currency-XOF .fx-flags .flag")
      assert text(doc, "#currency-LYD") =~ "à vérifier"
      assert text(doc, "#currency-hero") =~ "fawazahmed0/exchange-api"
      assert text(doc, "#currency-answer") =~ "11 novembre 2026"
    end

    test "against the euro, the CFA franc does not move and the page is out of the index",
         %{conn: conn} do
      doc = doc(conn, "/fr/monnaies?base=EUR")
      assert text(doc, "#currency-XOF") =~ "655,96"
      robots = doc |> LazyHTML.query(~s(meta[name="robots"])) |> LazyHTML.attribute("content")
      assert Enum.any?(robots, &(&1 =~ "noindex"))
    end

    test "the regime tabs filter the list", %{conn: conn} do
      doc = doc(conn, "/en/currencies?regime=EUR")
      codes = doc |> LazyHTML.query("#currency-list tbody tr") |> LazyHTML.attribute("id")

      assert Enum.sort(codes) ==
               ~w(currency-CVE currency-KMF currency-STN currency-XAF currency-XOF)
    end

    test "the converter works without a script", %{conn: conn} do
      doc = doc(conn, "/fr/monnaies?amount=100&from=EUR&to=XOF")
      assert text(doc, "#currency-result") =~ "65 596 XOF"
      doc = doc(conn, "/fr/monnaies?amount=abc&from=EUR&to=XOF")
      assert text(doc, "#currency-result") =~ "Saisissez un montant"
    end

    test "the page exists in every language with its alternates and a dataset", %{conn: conn} do
      for path <-
            ~w(/fr/monnaies /en/currencies /es/monedas /pt/moedas /ar/currencies /hi/currencies /zh/currencies) do
        doc = doc(conn, path)
        assert has?(doc, "#currency-list"), path
      end

      doc = doc(conn, "/fr/monnaies")
      json = doc |> LazyHTML.query(~s(script[type="application/ld+json"])) |> LazyHTML.text()
      assert json =~ "Dataset"
      assert json =~ "fawazahmed0"

      hreflangs =
        doc |> LazyHTML.query(~s(link[rel="alternate"])) |> LazyHTML.attribute("hreflang")

      assert "es" in hreflangs and "zh-Hans" in hreflangs
    end

    test "the country page shows the dollar, euro and yuan rates", %{conn: conn} do
      SyliAtlas.Fixtures.load_snapshot!()
      doc = doc(conn, "/fr/pays/nigeria/finances-et-dette")
      rates = text(doc, "#fx-rates")
      assert rates =~ "1 346"
      assert rates =~ "+6,6 %"
      assert has?(doc, ~s(#fx-rates [data-fx-base="CNY"]))
      assert text(doc, "#monnaie") =~ "fawazahmed0/exchange-api"

      doc = doc(conn, "/fr/pays/cote-d-ivoire/finances-et-dette")
      refute has?(doc, ~s(#fx-rates [data-fx-base="XOF"]))
      assert text(doc, "#fx-rates") =~ "655,96"
      assert text(doc, "#fx-rates") =~ "parité fixe"
    end

    test "the sitemap lists the page", %{conn: conn} do
      SyliAtlas.Fixtures.load_snapshot!()
      xml = conn |> get("/sitemaps/pages.xml") |> response(200)
      assert xml =~ "/fr/monnaies"
      assert xml =~ "/en/currencies"
    end
  end
end
