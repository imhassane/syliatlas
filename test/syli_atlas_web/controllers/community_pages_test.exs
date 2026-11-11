defmodule SyliAtlasWeb.CommunityPagesTest do
  use SyliAtlasWeb.ConnCase, async: false

  setup do
    SyliAtlas.Fixtures.load_snapshot!()
    :ok
  end

  defp doc(path), do: build_conn() |> get(path) |> html_response(200) |> LazyHTML.from_document()

  test "the communities page lists the six, in both languages" do
    doc = doc("/fr/communautes")
    assert doc |> LazyHTML.query("#communities-table tbody tr") |> Enum.count() == 6
    text = LazyHTML.text(doc)
    assert text =~ "CEDEAO" and text =~ "AES" and text =~ "SADC"
    assert LazyHTML.text(doc("/en/economic-communities")) =~ "ECOWAS"
  end

  test "a community: totals, members ranked, convergence for the UEMOA, sources" do
    doc = doc("/fr/communautes/uemoa")
    rows = LazyHTML.query(doc, "#members-table tbody tr")
    assert Enum.count(rows) == 8
    assert rows |> Enum.at(0) |> LazyHTML.text() =~ "Côte d'Ivoire"
    assert LazyHTML.query(doc, "#members-table .pill") |> Enum.count() > 0
    assert LazyHTML.text(doc) =~ "Source\u202f: FMI"

    links = doc |> LazyHTML.query("#members-table a") |> LazyHTML.attribute("href")
    assert "/fr/pays/senegal" in links
  end

  test "ECOWAS without the AES members; slugs across languages redirect; 404" do
    doc = doc("/fr/communautes/cedeao")
    assert doc |> LazyHTML.query("#members-table tbody tr") |> Enum.count() == 12
    refute LazyHTML.text(LazyHTML.query(doc, "#members-table")) =~ "Mali"
    assert redirected_to(get(build_conn(), "/fr/communautes/ecowas")) == "/fr/communautes/cedeao"
    assert_error_sent 404, fn -> get(build_conn(), "/fr/communautes/atlantide") end
  end
end
