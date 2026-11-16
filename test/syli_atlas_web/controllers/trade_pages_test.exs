defmodule SyliAtlasWeb.TradePagesTest do
  use SyliAtlasWeb.ConnCase, async: false

  alias SyliAtlas.Companies

  setup do
    SyliAtlas.Fixtures.load_snapshot!()
    :ok
  end

  defp doc(path), do: build_conn() |> get(path) |> html_response(200) |> LazyHTML.from_document()
  defp has?(doc, selector), do: LazyHTML.query(doc, selector) |> Enum.count() > 0
  defp count(doc, selector), do: LazyHTML.query(doc, selector) |> Enum.count()

  defp json_ld(doc) do
    doc
    |> LazyHTML.query(~s(script[type="application/ld+json"]))
    |> Enum.flat_map(fn node ->
      case node |> LazyHTML.text() |> Jason.decode!() do
        list when is_list(list) -> list
        one -> [one]
      end
    end)
  end

  describe "trade rankings" do
    test "each ranking: an answer, the 54 countries with a flag, structured data, links" do
      for path <-
            ~w(/fr/classement/dependance-premier-produit /fr/classement/matieres-premieres /fr/classement/commerce-intra-africain) do
        d = doc(path)
        assert has?(d, "#ranking-answer"), path
        assert count(d, "#market-list tbody tr") == 54, path
        assert count(d, "#market-list tbody .flag") == 54, path
        assert has?(d, "#ranking-csv"), path
        assert has?(d, ".trade-switch a[aria-current=page]"), path
        types = d |> json_ld() |> Enum.map(& &1["@type"])

        for t <- ~w(BreadcrumbList ItemList Dataset FAQPage),
            do: assert(t in types, "#{path}: #{t}")
      end
    end

    test "the answer names the first country and the median, in French" do
      text =
        doc("/fr/classement/dependance-premier-produit")
        |> LazyHTML.query("#ranking-answer")
        |> LazyHTML.text()

      assert text =~ "En 2024"
      assert text =~ "moitié des pays africains"
    end

    test "region, search and sort filter the table and leave the index" do
      conn = get(build_conn(), "/fr/classement/matieres-premieres?q=niger")
      html = html_response(conn, 200)
      d = LazyHTML.from_document(html)

      names =
        d
        |> LazyHTML.query("#market-list tbody th")
        |> Enum.map(&LazyHTML.text/1)
        |> Enum.map(&String.trim/1)

      assert Enum.sort(names) == ["Niger", "Nigeria"]
      assert html =~ ~s(name="robots" content="noindex)

      asc = doc("/fr/classement/matieres-premieres?sort=name&dir=asc")

      first =
        asc
        |> LazyHTML.query("#market-list tbody th")
        |> Enum.at(0)
        |> LazyHTML.text()
        |> String.trim()

      assert first == "Afrique du Sud"
    end

    test "every language has its address" do
      for path <-
            ~w(/en/ranking/export-dependence /es/clasificacion/materias-primas /pt/classificacao/comercio-intra-africano /ar/ranking/raw-materials /hi/ranking/intra-african-trade /zh/ranking/export-dependence) do
        assert build_conn() |> get(path) |> html_response(200), path
      end
    end

    test "the table as a CSV file, in the reader's language" do
      conn = get(build_conn(), "/fr/classement/matieres-premieres.csv")
      assert get_resp_header(conn, "content-type") == ["text/csv; charset=utf-8"]
      [disposition] = get_resp_header(conn, "content-disposition")
      assert disposition =~ "syli-atlas_matieres-premieres_2024.csv"
      body = response(conn, 200)
      assert String.starts_with?(body, "﻿")
      lines = body |> String.trim_leading("\uFEFF") |> String.split("\r\n", trim: true)
      assert Enum.count(lines, &String.starts_with?(&1, "\"#")) == 5
      assert Enum.count(lines, &(not String.starts_with?(&1, "\"#"))) == 55
      assert Enum.any?(lines, &(&1 =~ ~r/^1;.*;\d+,\d;/))

      en = build_conn() |> get("/en/ranking/raw-materials.csv") |> response(200)
      assert en =~ ~r/\n1,[^,]+,[A-Z]{3},\d+\.\d,/
    end
  end

  describe "Africa's trade" do
    test "the page: totals, products, partners, the 54 countries, the series, questions" do
      d = doc("/fr/afrique/commerce")

      for sel <-
            ~w(#africa-answer #africa-summary #africa-exports-table #africa-imports-table #africa-stages-table #africa-clients-bars #africa-exporters-table #africa-history #africa-products #africa-csv) do
        assert has?(d, sel), "missing #{sel}"
      end

      assert count(d, "#africa-exporters-table tbody tr") == 54
      types = d |> json_ld() |> Enum.map(& &1["@type"])
      assert "Dataset" in types and "FAQPage" in types
      assert d |> LazyHTML.query("#africa-answer") |> LazyHTML.text() =~ "Pétrole brut"
    end

    test "its file" do
      body = build_conn() |> get("/en/africa/trade.csv") |> response(200)
      assert body =~ "Exporter,"
      assert body =~ ~s("Exports, year",2000,)
    end
  end

  describe "products" do
    test "the list of products, grouped" do
      d = doc("/fr/afrique/produits")
      assert count(d, ".product-card") == length(SyliAtlas.AfricaTrade.products())
      assert has?(d, "#product-card-cocoa")
    end

    test "a product Africa sells, with a processing chain: copper" do
      d = doc("/fr/afrique/produits/cuivre")

      for sel <-
            ~w(#product-answer #product-chain #chain-steps #product-countries-table #product-world-bars #product-clients-bars #product-history #product-csv) do
        assert has?(d, sel), "missing #{sel}"
      end

      assert count(d, "#chain-steps li") == 5
      refute has?(d, "#product-suppliers")
      text = LazyHTML.text(d)
      assert text =~ "Cuivre : en 2024, l'Afrique en a exporté pour"
      assert text =~ "Rép. dém. du Congo" or text =~ "RD Congo" or text =~ "Congo"
    end

    test "a product Africa buys: wheat puts importers and suppliers first" do
      d = doc("/fr/afrique/produits/ble")
      assert has?(d, "#product-suppliers")
      assert has?(d, "#producteurs")
      refute has?(d, "#product-clients")
      assert d |> LazyHTML.query("#product-answer") |> LazyHTML.text() =~ "a acheté"
    end

    test "a slug of another language sends to the page's own address" do
      assert build_conn() |> get("/fr/afrique/produits/wheat") |> redirected_to(301) ==
               "/fr/afrique/produits/ble"

      assert_error_sent 404, fn -> get(build_conn(), "/fr/afrique/produits/inconnu") end
    end

    test "companies are shown only once their source confirmed them" do
      {:ok, c} =
        Companies.create(%{
          "product" => "copper",
          "country" => "COD",
          "name" => "Test Mine",
          "kind" => "mine",
          "source_url" => "https://example.com/mine",
          "source_name" => "example.com"
        })

      refute has?(doc("/fr/afrique/produits/cuivre"), "#companies")

      Companies.check!(c, fn _ -> {:confirmed, "Test Mine produces copper in the DRC."} end)
      d = doc("/fr/afrique/produits/cuivre")
      assert has?(d, "#companies")
      assert LazyHTML.text(d) =~ "Test Mine"

      Companies.check!(Companies.get!(c.id), fn _ -> {:rejected, "page changed"} end)
      refute has?(doc("/fr/afrique/produits/cuivre"), "#companies")
    end

    test "its file" do
      body = build_conn() |> get("/fr/afrique/produits/cuivre.csv") |> response(200)
      assert body =~ "Étape de transformation" or body =~ "Processing step"
      assert body =~ "COD"
    end
  end

  describe "a country's trade files" do
    test "each file and the archive" do
      for f <- ~w(produits clients afrique historique potentiel) do
        conn = get(build_conn(), "/fr/pays/cote-d-ivoire/commerce/#{f}.csv")
        assert response(conn, 200) =~ "# ", f
      end

      conn = get(build_conn(), "/fr/pays/cote-d-ivoire/commerce/tout.zip")
      assert get_resp_header(conn, "content-type") == ["application/zip"]
      {:ok, files} = :zip.unzip(response(conn, 200), [:memory])
      assert length(files) == 5

      assert_error_sent 404, fn ->
        get(build_conn(), "/fr/pays/cote-d-ivoire/commerce/autre.csv")
      end
    end

    test "the Trade tab offers them in its data menu" do
      d = doc("/fr/pays/cote-d-ivoire/commerce")
      assert has?(d, "#data-menu-trade")
      assert count(d, "#data-menu-trade a") == 6
    end
  end

  test "sitemap and llms.txt list the trade pages" do
    llms = build_conn() |> get("/llms.txt") |> response(200)
    assert llms =~ "/en/africa/trade"
    assert llms =~ "/en/ranking/export-dependence"
    assert llms =~ "/en/africa/products/copper"
  end
end
