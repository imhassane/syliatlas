defmodule SyliAtlasWeb.MotionTest do
  @moduledoc "The hooks of page transitions and of the sticky header, in the HTML."
  use SyliAtlasWeb.ConnCase, async: false

  defp doc(path), do: build_conn() |> get(path) |> html_response(200) |> LazyHTML.from_document()
  defp count(html, selector), do: html |> LazyHTML.query(selector) |> Enum.count()

  setup do
    SyliAtlas.Fixtures.load_snapshot!()
    SyliAtlas.MarketFixtures.import!()
    :ok
  end

  test "every public page: sticky header with its band, progress, back to top, render mark" do
    for path <- ["/fr", "/fr/bourses", "/fr/notations", "/fr/pays/cote-d-ivoire"] do
      html = doc(path)
      assert count(html, "#site-top > header.site-header") == 1, path
      assert count(html, "#site-top > #site-ticker") == 1, path
      assert count(html, ".read-progress[aria-hidden=true]") == 1
      assert count(html, "button#to-top[hidden][aria-label]") == 1
      assert count(html, "main#main #vt-ready") == 1
      assert count(html, ~s(link[rel=expect][href="#vt-ready"][blocking=render])) == 1
    end
  end

  test "pages are prepared on hover, never the account, admin or API" do
    [rules] =
      doc("/fr")
      |> LazyHTML.query(~s(script[type=speculationrules]))
      |> Enum.map(&LazyHTML.text/1)

    rules = Jason.decode!(rules)

    [
      %{
        "eagerness" => "moderate",
        "where" => %{"and" => [_, %{"not" => %{"href_matches" => excluded}}, _]}
      }
    ] =
      rules["prerender"]

    for p <- ["/admin/*", "/api/*", "/*/mon-espace*", "/*/connexion*"], do: assert(p in excluded)
  end

  test "a country profile: one underline under the current tab, the tab content in a panel" do
    html = doc("/fr/pays/cote-d-ivoire/economie")
    assert count(html, "#profile-tabs .tab-indicator") == 1
    assert count(html, ~s(#profile-tabs a[aria-current=page] .tab-indicator)) == 1
    assert count(html, "main > .tab-panel") == 1
  end

  test "tables that filter and sort mark their rows and their place" do
    html = doc("/fr/bourses")
    assert count(html, "#market-table[data-keep-place]") == 1
    assert count(html, "#market-list tbody[data-reorder] > tr[id]") == 21

    html = doc("/fr/notations")
    assert count(html, "#ratings-table[data-keep-place]") == 1
    assert count(html, "#ratings-rows tbody[data-reorder] > tr[id]") > 0
  end

  test "sign-in pages keep the header but have no band" do
    html = doc("/fr/connexion")
    assert count(html, "#site-top > header.site-header") == 1
    assert count(html, "#site-ticker") == 0
  end
end
