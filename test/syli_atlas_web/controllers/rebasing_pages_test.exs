defmodule SyliAtlasWeb.RebasingPagesTest do
  @moduledoc """
  The rebasing alert on the public pages (decisions of 15 Nov. 2026): chip,
  folded panel in the Economy tab, note on Public finances, title,
  description and structured data, the page of every rebasing, the sitemap
  and the admin.
  """
  use SyliAtlasWeb.ConnCase, async: false
  use Oban.Testing, repo: SyliAtlas.Repo, engine: Oban.Engines.Lite

  alias SyliAtlas.{National, Repo}
  alias SyliAtlas.National.{Rebasing, Rebasings}
  alias SyliAtlasWeb.RebasingComponents

  setup %{conn: conn} do
    SyliAtlas.Fixtures.load_snapshot!()
    {:ok, admin: SyliAtlas.AccountsFixtures.admin_conn(conn)}
  end

  defp doc(conn, path), do: conn |> get(path) |> html_response(200) |> LazyHTML.from_document()
  defp text(doc, sel), do: doc |> LazyHTML.query(sel) |> LazyHTML.text()
  defp count(doc, sel), do: doc |> LazyHTML.query(sel) |> Enum.count()
  defp attr(doc, sel, name), do: doc |> LazyHTML.query(sel) |> LazyHTML.attribute(name)

  defp json_ld(doc) do
    doc
    |> LazyHTML.query("script[type='application/ld+json']")
    |> Enum.map(&(&1 |> LazyHTML.text() |> Jason.decode!()))
  end

  test "every tab carries the chip; it leads to the panel of the Economy tab", %{conn: conn} do
    for path <- ["/fr/pays/ethiopie", "/fr/pays/ethiopie/finances-et-dette"] do
      d = doc(conn, path)
      assert text(d, "#rebasing-chip") =~ "PIB rebasé le 4 nov. 2026 · +59,2"
      assert attr(d, "#rebasing-chip", "href") == ["/fr/pays/ethiopie/economie#rebasage"]
    end

    d = doc(conn, "/fr/pays/ethiopie")
    assert count(d, "#rebasage") == 0
    assert text(d, "#country-kpis") =~ "ancienne base"
  end

  test "the Economy tab has the panel, folded, in the HTML served", %{conn: conn} do
    d = doc(conn, "/fr/pays/ethiopie/economie")
    assert count(d, "details#rebasage") == 1
    assert attr(d, "details#rebasage", "open") == []
    panel = text(d, "#rebasage")
    assert panel =~ "PIB réévalué de +59,2"
    assert panel =~ "le FMI ne l'a pas encore intégré"
    assert panel =~ RebasingComponents.next_edition("fr")
    assert panel =~ "2024/25 (au lieu de 2015/16)"
    assert panel =~ "2015/16 → 2024/25"
    assert count(d, "#rebasage a[href='/fr/rebasages-pib']") == 1
  end

  test "Public finances: ratios to GDP on the former base", %{conn: conn} do
    d = doc(conn, "/fr/pays/ethiopie/finances-et-dette")
    assert text(d, "#rebasing-ratio-note") =~ "ancienne base du PIB"
  end

  test "title, description and structured data say it while it is active", %{conn: conn} do
    d = doc(conn, "/fr/pays/ethiopie")
    assert text(d, "title") =~ "Éthiopie : PIB rebasé (+59,2"

    [desc] = attr(d, "meta[name='description']", "content")

    assert desc =~ "L’Éthiopie a rebasé son PIB le 4 nov. 2026" or
             desc =~ "L'Éthiopie a rebasé son PIB le 4 nov. 2026"

    assert desc =~ "prochaine édition de ses Perspectives"

    dataset = d |> json_ld() |> Enum.find(&(&1["@type"] == "Dataset"))
    assert dataset["description"] =~ "a rebasé son PIB"
    assert dataset["dateModified"] >= "2026-11-04"

    assert text(doc(conn, "/fr/pays/ethiopie/economie"), "title") =~ "rebasé (+59,2"
  end

  test "a country without rebasing: nothing", %{conn: conn} do
    d = doc(conn, "/fr/pays/tchad/economie")
    assert count(d, "#rebasing-chip") == 0
    assert count(d, "#rebasage") == 0
    refute text(d, "#country-kpis") =~ "ancienne base"
    refute text(d, "title") =~ "rebasé"
  end

  test "once the IMF has taken it in: a line of history, no more alert", %{conn: conn} do
    Rebasings.mark_integrated!(Repo.get_by!(Rebasing, country_code: "ETH"), "admin@test")

    d = doc(conn, "/fr/pays/ethiopie/economie")
    assert count(d, "#rebasing-chip") == 0
    assert count(d, "#rebasage") == 0
    assert text(d, "#rebasing-history") =~ "intégré par le FMI"
    refute text(d, "title") =~ "rebasé"
  end

  test "the page of every rebasing, in every language and in the sitemap", %{conn: conn} do
    d = doc(conn, "/fr/rebasages-pib")
    assert text(d, "h1") =~ "Rebasages du PIB en Afrique"
    assert count(d, "#rebasing-table tbody tr") == 5
    assert text(d, "#rebasing-row-ETH") =~ "+59,2"
    assert text(d, "#rebasing-row-ETH") =~ "Pas encore"
    assert attr(d, "#rebasing-row-ETH a", "href") |> hd() == "/fr/pays/ethiopie/economie#rebasage"
    assert text(d, "#rebasing-row-SEN") =~ "2014 → 2021"
    assert d |> json_ld() |> Enum.any?(&(&1["@type"] == "Dataset"))

    assert conn |> get("/en/gdp-rebasings") |> html_response(200) =~ "GDP rebasings in Africa"

    assert {%{"fr" => "/fr/rebasages-pib"}, lastmod} =
             Enum.find(SyliAtlasWeb.SitemapController.pages(), fn {paths, _} ->
               paths["fr"] == "/fr/rebasages-pib"
             end)

    assert lastmod >= "2026-11-04"
  end

  test "the admin: proposals published or set aside, alerts closed by hand", %{
    conn: conn,
    admin: admin
  } do
    assert redirected_to(post(conn, "/admin/chiffres-nationaux/rebasages/veille")) ==
             "/fr/connexion"

    {:ok, p} =
      Rebasings.propose(%{
        "country_code" => "GHA",
        "announced_on" => "2026-11-10",
        "new_base" => "2023",
        "origin" => "watch",
        "article_url" => "https://news.test/gha",
        "excerpt" => "Ghana's statistical service rebased its GDP to 2023."
      })

    d = doc(admin, "/admin/chiffres-nationaux")
    assert count(d, "#rebasing-#{p.id}") == 1
    assert text(d, "#adm-rebasing-list") =~ "Éthiopie"

    post(admin, "/admin/chiffres-nationaux/rebasages/#{p.id}/publier", %{
      "rebasing" => %{
        "old_base" => "2013",
        "new_base" => "2023",
        "announced_on" => "2026-11-10",
        "level_change_pct" => "24,5",
        "source_name" => "Ghana Statistical Service",
        "source_url" => "https://statsghana.gov.gh/rebasing"
      }
    })

    assert National.rebasing(National.document(), "GHA")["active"]
    assert text(doc(conn, "/fr/pays/ghana"), "#rebasing-chip") =~ "+24,5"

    post(admin, "/admin/chiffres-nationaux/rebasages", %{
      "rebasing" => %{
        "country_code" => "KEN",
        "announced_on" => "2026-11-12",
        "old_base" => "2016",
        "new_base" => "2024",
        "source_name" => "KNBS",
        "source_url" => "https://knbs.or.ke/rebasing"
      }
    })

    assert text(doc(conn, "/fr/pays/kenya"), "#rebasing-chip") =~ "PIB rebasé le 12 nov. 2026"

    ken = Repo.get_by!(Rebasing, country_code: "KEN")
    post(admin, "/admin/chiffres-nationaux/rebasages/#{ken.id}/integre")
    refute National.rebasing(National.document(), "KEN")["active"]

    post(admin, "/admin/chiffres-nationaux/rebasages/veille")
    assert [_] = all_enqueued(worker: SyliAtlas.Workers.RebasingWatchWorker)
  end
end
