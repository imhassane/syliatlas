defmodule SyliAtlasWeb.ExportControllerTest do
  @moduledoc "An area's figures as CSV, Excel and JSON files, and the « Data » menu."
  use SyliAtlasWeb.ConnCase, async: false

  setup do
    SyliAtlas.Fixtures.load_snapshot!()
    :ok
  end

  defp download(path) do
    conn = get(build_conn(), path)
    assert conn.status == 200, "#{path}: #{conn.status}"
    conn
  end

  defp header(conn, name), do: conn |> get_resp_header(name) |> List.first()

  test "CSV in French: semicolons, decimal commas, sources, BOM, period of the page" do
    conn = download("/fr/pays/cote-d-ivoire/donnees.csv?from=2020&to=2025")
    body = conn.resp_body

    assert header(conn, "content-type") =~ "text/csv"

    assert header(conn, "content-disposition") =~
             ~s(filename="syli-atlas_cote-d-ivoire_2020-2025.csv")

    assert String.starts_with?(body, "﻿")
    assert body =~ "Fonds monétaire international, Perspectives de l'économie mondiale"
    assert body =~ "CC BY 4.0"
    assert body =~ "https://www.imf.org/en/About/copyright-and-terms"
    assert body =~ "Indicateur;Unité;2020;2021;2022;2023;2024;2025"
    refute body =~ ";2026"

    [growth] =
      body
      |> String.split("\r\n")
      |> Enum.filter(&String.starts_with?(&1, "Croissance du PIB réel;"))

    cells = String.split(growth, ";")
    assert length(cells) == 2 + 6
    assert Enum.any?(cells, &(&1 =~ ~r/^-?\d+,\d+$/)), "decimal comma expected: #{growth}"

    assert body =~ ~r/Statut de l'année;;observé;.*;estimation\r\n/
  end

  test "CSV in English: commas and decimal points; sep= overrides the habit" do
    body = download("/en/countries/cote-d-ivoire/data.csv?from=2015&to=2030").resp_body
    assert body =~ "Indicator,Unit,2015,"
    assert body =~ ",2030\r\n"
    assert body =~ "projection"
    refute body =~ "Indicator;Unit"

    body = download("/fr/pays/cote-d-ivoire/donnees.csv?sep=comma").resp_body
    assert body =~ "Indicateur,Unité,"
  end

  test "Excel: a real .xlsx with a sheet of figures and a sheet of sources" do
    conn = download("/fr/pays/cote-d-ivoire/donnees.xlsx?from=2020&to=2025")
    assert header(conn, "content-type") =~ "spreadsheetml.sheet"
    assert header(conn, "content-disposition") =~ ".xlsx"

    {:ok, files} = :zip.unzip(conn.resp_body, [:memory])
    files = Map.new(files, fn {name, bytes} -> {to_string(name), bytes} end)

    assert Map.has_key?(files, "[Content_Types].xml")
    assert files["xl/workbook.xml"] =~ ~s(name="Données")
    assert files["xl/workbook.xml"] =~ ~s(name="À propos")
    assert files["xl/worksheets/sheet1.xml"] =~ "Croissance du PIB réel"
    # Figures are numbers, not text.
    assert files["xl/worksheets/sheet1.xml"] =~ ~r{<c r="C2"><v>-?\d+(\.\d+)?</v></c>}
    assert files["xl/worksheets/sheet2.xml"] =~ "Fonds monétaire international"
  end

  test "JSON: the public API's answer, as a file" do
    conn = download("/fr/pays/cote-d-ivoire/donnees.json?from=2020&to=2025")
    assert header(conn, "content-type") =~ "application/json"

    assert %{"data" => %{"code" => "CIV"}, "meta" => %{"sources" => [_ | _], "from" => 2020}} =
             Jason.decode!(conn.resp_body)
  end

  test "regions and the continent export; a country address does not serve a region" do
    assert download("/fr/regions/afrique-de-l-ouest/donnees.csv").resp_body =~
             "Afrique de l'Ouest"

    assert download("/en/regions/africa/data.xlsx").status == 200

    assert_error_sent 404, fn -> get(build_conn(), "/fr/pays/afrique-de-l-ouest/donnees.csv") end
    assert_error_sent 404, fn -> get(build_conn(), "/fr/pays/atlantide/donnees.csv") end
  end

  test "any Accept header: scripts and spreadsheets ask for text/csv" do
    conn =
      build_conn() |> put_req_header("accept", "text/csv") |> get("/fr/pays/senegal/donnees.csv")

    assert conn.status == 200
  end

  test "the profile header offers the files of the period shown and the embed page" do
    html =
      build_conn()
      |> get("/fr/pays/cote-d-ivoire?from=2015&to=2025")
      |> html_response(200)
      |> LazyHTML.from_document()

    href = fn id -> html |> LazyHTML.query(id) |> LazyHTML.attribute("href") |> List.first() end
    assert href.("#data-csv") == "/fr/pays/cote-d-ivoire/donnees.csv?from=2015&to=2025"
    assert href.("#data-xlsx") == "/fr/pays/cote-d-ivoire/donnees.xlsx?from=2015&to=2025"
    assert href.("#embed-link") == "/fr/pays/cote-d-ivoire/integrer"

    region = build_conn() |> get("/fr/regions/afrique-de-l-ouest") |> html_response(200)
    assert region =~ "/fr/regions/afrique-de-l-ouest/donnees.csv"
  end

  test "no stock price leaves in a file" do
    body = download("/fr/pays/cote-d-ivoire/donnees.csv").resp_body
    refute body =~ "Sonatel"
    # Only the line that says they are left out.
    assert body =~ "non redistribuables"
  end
end
