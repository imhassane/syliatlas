defmodule SyliAtlasWeb.BudgetPagesTest do
  use SyliAtlasWeb.ConnCase, async: false

  alias SyliAtlas.BudgetFixtures

  setup do
    SyliAtlas.Fixtures.load_snapshot!()
    SyliAtlas.Budgets.seed!()
    :ok
  end

  defp doc(conn, path), do: conn |> get(path) |> html_response(200) |> LazyHTML.from_document()
  defp has?(doc, selector), do: LazyHTML.query(doc, selector) |> Enum.count() > 0
  defp text(doc, selector), do: doc |> LazyHTML.query(selector) |> LazyHTML.text()
  defp attr(doc, selector, name), do: doc |> LazyHTML.query(selector) |> LazyHTML.attribute(name)

  describe "the budgets page" do
    test "lists the 54 countries with the IMF figures and who votes", %{conn: conn} do
      doc = doc(conn, "/fr/budgets")
      assert text(doc, "h1") =~ "Les budgets des 54 États africains"
      assert LazyHTML.query(doc, "#budgets-rows tbody tr") |> Enum.count() == 54
      assert text(doc, "#budget-MLI") =~ "Organe de transition"
      assert text(doc, "#budget-NER") =~ "Aucun parlement"
      # Scrolls inside its card, reachable with the keyboard.
      assert has?(
               doc,
               ~s(.table-scroll[tabindex="0"][role="region"][aria-labelledby="budgets-caption"])
             )

      assert text(doc, "#budget-MLI") =~ "Estimation FMI"
      assert text(doc, "[data-answer]") =~ "dépensent en médiane"
      assert attr(doc, "#budget-MLI th a", "href") == ["/fr/pays/mali/budget"]
      # No law yet: no latest laws, no currency list.
      refute has?(doc, "#budget-latest")
      # Accessible table: caption, column headers, a label on each cell for phones.
      assert has?(doc, "#budgets-rows caption")
      assert has?(doc, ~s(#budgets-rows th[scope="col"][aria-sort="descending"]))
      assert has?(doc, "#budget-MLI td[data-label]")
    end

    test "sorts and filters through the address", %{conn: conn} do
      doc = doc(conn, "/fr/budgets?region=west_africa&sort=name")

      names =
        doc
        |> LazyHTML.query("#budgets-rows tbody th")
        |> Enum.map(&LazyHTML.text/1)
        |> Enum.map(&String.trim/1)

      assert hd(names) == "Bénin"
      assert length(names) == 15
      assert has?(doc, ~s(th[aria-sort="ascending"]))
    end

    test "the latest laws, amounts in euros with the local amount under them", %{conn: conn} do
      SyliAtlas.FxFixtures.import!()
      BudgetFixtures.publish!()

      doc = doc(conn, "/fr/budgets")
      assert text(doc, "#budget-latest") =~ "Loi de finances rectificative 2026"
      money = LazyHTML.query(doc, "#budget-latest [data-money]")
      assert LazyHTML.attribute(money, "data-currency") == ["XOF"]
      # 3 993 319 000 000 XOF at 655,957 per euro: 6,09 billion euros.
      assert text(doc, "#budget-latest [data-money-main]") =~ "6,09 Md €"
      assert text(doc, "#budget-latest [data-money-local]") =~ "3 993 Md XOF"
      assert has?(doc, "[data-money-picker][hidden] select#latest-money-picker")
      assert text(doc, "[data-money-rates]") =~ "XOF"
      assert text(doc, "#budget-MLI") =~ "Rectificative 2026 · Votée"
    end

    test "is in the menu, the sitemap and the search", %{conn: conn} do
      doc = doc(conn, "/fr")
      assert has?(doc, ~s(.nav-mega a[href="/fr/budgets"]))

      sitemap = sitemaps()
      assert sitemap =~ "/fr/budgets</loc>"
      assert sitemap =~ "/fr/pays/mali/budget</loc>"
      assert sitemap =~ "/en/countries/mali/budget</loc>"

      result = SyliAtlasWeb.Search.run("budget mali", "fr")
      assert hd(result["results"])["path"] == "/fr/pays/mali/budget"
      _ = conn
    end

    test "exists in every language of the site", %{conn: conn} do
      assert conn |> get("/en/budgets") |> html_response(200) =~
               "State budgets of the 54 African countries"

      assert build_conn() |> get("/es/presupuestos") |> html_response(200)
      assert build_conn() |> get("/pt/orcamentos") |> html_response(200)
    end
  end

  describe "the budget tab of a country" do
    test "without a law: the IMF figures, who votes, and why there is no law yet", %{conn: conn} do
      doc = doc(conn, "/fr/pays/mali/budget")

      assert attr(doc, ~s(#profile-tabs a[aria-current="page"]), "href") == [
               "/fr/pays/mali/budget"
             ]

      assert text(doc, "#budget h2") =~ "Mali : des dépenses publiques à"
      assert text(doc, "#budget .lead") =~ "Aucune loi de finances du Mali"
      assert has?(doc, "#budget-empty")
      assert text(doc, "#budget-who") =~ "Conseil national de Transition"
      assert text(doc, "#budget-who") =~ "organe de transition"
      assert text(doc, "#budget-who") =~ "Journal officiel de la République du Mali"
      assert attr(doc, "#budget-who a", "href") == ["https://sgg-mali.ml"]
      assert LazyHTML.query(doc, "#budget-imf-table tbody tr") |> Enum.count() == 7
      assert text(doc, "[data-budget-level]") =~ "Estimation FMI"
      assert text(doc, "title") =~ "Budget de l'État du Mali"
      refute has?(doc, "[data-money-picker]")
    end

    test "with laws: the laws one by one, the timeline, amounts in the reader's currency", %{
      conn: conn
    } do
      SyliAtlas.FxFixtures.import!()

      BudgetFixtures.publish!(%{
        "kind" => "initial",
        "voted_on" => "2025-12-04",
        "published_on" => "2025-12-18",
        "revenue" => "3057790000000",
        "expenditure" => "3578217000000"
      })

      BudgetFixtures.publish!()

      doc = doc(conn, "/fr/pays/mali/budget")
      assert text(doc, "#budget h2") =~ "6,09 Md € de dépenses autorisées pour 2026"

      assert text(doc, "#budget .lead") =~
               "Loi de finances rectificative 2026 du Mali autorise 3 993 Md XOF"

      assert text(doc, "[data-budget-level]") =~ "Loi de finances officielle"
      rows = LazyHTML.query(doc, "#budget-laws tbody tr")
      assert Enum.count(rows) == 2

      assert text(doc, "#budget-laws tbody tr:first-child") =~
               "Loi de finances rectificative 2026"

      assert attr(doc, "#budget-laws tbody tr:first-child a", "href") == [
               "https://sgg-mali.ml/JO/2026/mali-jo-2026-15.pdf"
             ]

      assert text(doc, "#budget-timeline") =~ "121 pour" or
               text(doc, "#budget-timeline") =~ "121 voix pour"

      assert text(doc, "#budget-timeline li:first-child") =~ "votée"

      assert text(doc, ~s([data-kpi="budget-balance"])) =~ "−621 Md XOF" or
               text(doc, ~s([data-kpi="budget-balance"])) =~ "−620 Md XOF"

      assert has?(doc, "[data-money-picker] select option[value=XOF]")
      refute has?(doc, "#budget-empty")
    end

    test "every country has the tab, in English too" do
      for slug <- ~w(niger erythree soudan afrique-du-sud) do
        assert build_conn() |> get("/fr/pays/#{slug}/budget") |> html_response(200) =~
                 ~s(id="budget")
      end

      html = build_conn() |> get("/en/countries/niger/budget") |> html_response(200)
      assert html =~ "No legislature votes the budget"
    end
  end
end
