defmodule SyliAtlasWeb.SearchTest do
  use SyliAtlasWeb.ConnCase, async: false

  alias SyliAtlasWeb.Search

  setup do
    SyliAtlas.Fixtures.load_snapshot!()
    SyliAtlasWeb.Search.Index.reset()
    :ok
  end

  defp first(q, locale \\ "fr"), do: hd(Search.run(q, locale)["results"])

  test "names in both languages, ISO codes and other usual names" do
    for q <- ["Côte d'Ivoire", "cote divoire", "Ivory Coast", "CIV", "RCI"] do
      assert first(q)["code"] == "CIV", q
    end

    assert first("RDC")["code"] == "COD"
    assert first("congo brazzaville")["code"] == "COG"
    assert first("Swaziland")["code"] == "SWZ"
    assert first("South Africa", "en")["path"] == "/en/countries/south-africa"
  end

  test "typos and prefixes" do
    assert first("senegl")["code"] == "SEN"
    assert first("nigria")["code"] == "NGA"
    assert first("madagascr")["code"] == "MDG"
    assert first("ethio")["code"] == "ETH"
  end

  test "a country and a theme: the tab, and the figure as direct answer" do
    r = Search.run("dette du Sénégal", "fr")
    assert hd(r["results"])["path"] == "/fr/pays/senegal/finances-et-dette"
    assert r["answer"]["indicator"] == "public_debt_pct_gdp"
    assert r["answer"]["value"] =~ "%"
    assert r["answer"]["path"] == "/fr/pays/senegal/finances-et-dette"

    assert Search.run("inflation kenya", "en")["answer"]["indicator"] == "inflation"
    assert hd(Search.run("exports ghana", "en")["results"])["path"] == "/en/countries/ghana/trade"
    assert hd(Search.run("notation maroc", "fr")["results"])["path"] == "/fr/pays/maroc/marches"
  end

  test "communities, regions and theme pages" do
    assert first("UEMOA")["path"] == "/fr/communautes/uemoa"
    assert first("ECOWAS", "en")["path"] == "/en/economic-communities/ecowas"
    assert first("cedeao")["path"] == "/fr/communautes/cedeao"
    assert first("afrique de l'ouest")["path"] == "/fr/regions/afrique-de-l-ouest"
    assert first("dette")["path"] == "/fr/dette"
    assert first("notations")["path"] == "/fr/notations"
  end

  test "nothing for gibberish, and only names in full get the answer" do
    assert Search.run("zzqqxx", "fr")["results"] == []
    assert Search.run("se", "fr")["answer"] == nil
  end

  test "the search page: exact name redirects, several results list, misses are counted" do
    assert redirected_to(get(build_conn(), "/fr/recherche?q=senegal")) == "/fr/pays/senegal"

    assert redirected_to(get(build_conn(), "/fr/recherche?q=dette+senegal")) ==
             "/fr/pays/senegal/finances-et-dette"

    html = build_conn() |> get("/fr/recherche?q=guin") |> html_response(200)
    assert html =~ "Guinée-Bissau" and html =~ "Guinée équatoriale"

    html = build_conn() |> get("/fr/recherche?q=zzqqxx") |> html_response(200)
    assert html =~ ~s(id="search-none")
    get(build_conn(), "/fr/recherche?q=ZZQQXX")
    assert [%{query: "zzqqxx", count: 2, locale: "fr"}] = SyliAtlas.Search.Miss.top()
  end

  test "the JSON API, used by the suggestions" do
    body = build_conn() |> get("/api/v1/search?q=dette+senegal&locale=fr") |> json_response(200)
    assert hd(body["results"])["path"] == "/fr/pays/senegal/finances-et-dette"
    assert body["answer"]["source"] =~ "FMI"
    en = build_conn() |> get("/api/v1/search?q=nigeria&locale=en") |> json_response(200)
    assert hd(en["results"])["path"] == "/en/countries/nigeria"
    assert hd(en["results"])["kind"] == "Country"
  end

  test "the admin lists the misses" do
    SyliAtlas.Search.Miss.record("wakanda", "fr")
    auth = Plug.BasicAuth.encode_basic_auth("admin", "test-password")

    html =
      build_conn()
      |> put_req_header("authorization", auth)
      |> get("/admin/recherches")
      |> html_response(200)

    assert html =~ "wakanda"
  end
end
