defmodule SyliAtlasWeb.AccessibilityTest do
  use SyliAtlasWeb.ConnCase, async: false

  setup do
    SyliAtlas.Fixtures.load_snapshot!()
    :ok
  end

  test "the statement is published in French and English, each pointing to the other",
       %{conn: conn} do
    fr = conn |> get("/fr/accessibilite") |> html_response(200)
    assert fr =~ ~s(id="accessibility-statement")
    assert fr =~ "non conforme"
    assert fr =~ "Défenseur des droits"
    assert fr =~ ~r{hreflang="en" href="[^"]+/en/accessibility"}

    en = build_conn() |> get("/en/accessibility") |> html_response(200)
    assert en =~ "not compliant"
    assert en =~ ~r{hreflang="fr" href="[^"]+/fr/accessibilite"}
  end

  test "every page states its compliance in the footer, linked to the statement",
       %{conn: conn} do
    html = conn |> get("/fr") |> html_response(200)

    assert html =~
             ~r{<a href="/fr/accessibilite" id="footer-accessibility">\s*Accessibilité : non conforme}
  end

  test "the statement is in the sitemap", %{conn: conn} do
    assert conn |> get("/sitemap.xml") |> response(200) =~ "/fr/accessibilite</loc>"
  end

  test "the contact address shows only once it is set", %{conn: conn} do
    refute conn |> get("/fr/accessibilite") |> html_response(200) =~ "mailto:"

    previous = Application.get_env(:syli_atlas, :site)
    Application.put_env(:syli_atlas, :site, contact_email: "a11y@example.org")

    on_exit(fn ->
      if previous,
        do: Application.put_env(:syli_atlas, :site, previous),
        else: Application.delete_env(:syli_atlas, :site)
    end)

    html = build_conn() |> get("/fr/accessibilite") |> html_response(200)
    assert html =~ "mailto:a11y@example.org"
    # Cloudflare would replace it with « [email protected] », decoded only by script.
    assert html =~ ~r{<!--email_off-->\s*<a href="mailto:a11y@example.org"}
  end

  test "each chart comes with its values as a table", %{conn: conn} do
    html = conn |> get("/fr/pays/senegal/economie") |> html_response(200)
    assert html =~ ~r{<details[^>]*class="chart-data"}
    assert html =~ "Données du graphique en tableau"
  end

  test "each country of the map says its value, not only its colour", %{conn: conn} do
    html = conn |> get("/fr") |> html_response(200)
    assert html =~ ~r{data-name="Sénégal"\s+aria-label="Sénégal : [^"]+"}
  end

  test "search forms have distinct names", %{conn: conn} do
    html = conn |> get("/fr") |> html_response(200)
    assert html =~ ~s(aria-label="Recherche dans le site")
    assert html =~ ~s(aria-label="Rechercher dans les données")
  end
end
