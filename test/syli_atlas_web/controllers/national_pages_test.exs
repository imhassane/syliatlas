defmodule SyliAtlasWeb.NationalPagesTest do
  @moduledoc """
  National figures on the public pages (fiche, home window and map, the
  country-by-country page) and their review in the admin.
  """
  use SyliAtlasWeb.ConnCase, async: false

  alias SyliAtlas.National

  setup %{conn: conn} do
    SyliAtlas.Fixtures.load_snapshot!()
    {:ok, admin: SyliAtlas.AccountsFixtures.admin_conn(conn)}
  end

  defp doc(conn, path), do: conn |> get(path) |> html_response(200) |> LazyHTML.from_document()
  defp text(doc, sel), do: doc |> LazyHTML.query(sel) |> LazyHTML.text()
  defp count(doc, sel), do: doc |> LazyHTML.query(sel) |> Enum.count()

  test "the Ethiopian page shows the rebasing, both figures and the badge", %{conn: conn} do
    d = doc(conn, "/fr/pays/ethiopie/economie")

    assert text(d, "#national-rebasing") =~ "2024/25 au lieu de 2015/16"
    assert text(d, "#national-card-gdp_usd_bn") =~ "201,4"
    assert text(d, "#national-card-gdp_usd_bn") =~ "126,4"
    assert text(d, "#national-card-gdp_usd_bn") =~ "En cours de vérification"
    assert text(d, "#national-card-public_debt_pct_gdp") =~ "27,4"
    assert text(d, "#national-card-gdp_per_capita") =~ "calcul Syli Atlas"
    # Official marks on the chart, never a point of the IMF line.
    assert count(d, "#area-chart .national-mark.is-wait") == 2

    [tips | _] =
      d
      |> LazyHTML.query("#area-chart-figure [data-chart-tips]")
      |> LazyHTML.attribute("data-chart-tips")

    p2025 = tips |> Jason.decode!() |> Map.fetch!("points") |> Enum.find(&(&1["year"] == 2025))
    assert p2025["national"]["text"] =~ "201,4"
    assert p2025["national"]["wait"]
    assert p2025["valuetext"] =~ "Officiel · 2024/25"
  end

  test "a country without national figures shows none", %{conn: conn} do
    d = doc(conn, "/fr/pays/ghana/economie")
    assert count(d, "#national-figures") == 0
    assert count(d, "#national-rebasing") == 0
  end

  test "the home window shows the sum, the composition and the pending figure", %{conn: conn} do
    d = doc(conn, "/fr")
    sum = text(d, "#national-sum")
    assert sum =~ "Somme des chiffres nationaux"
    assert sum =~ "0 pays au chiffre officiel"
    assert sum =~ "53 au chiffre FMI (repli)"
    assert sum =~ "En cours de vérification"
    assert sum =~ "3 252"
    assert count(d, "#national-sum a[href='/fr/chiffres-nationaux']") == 1
  end

  test "the map marks the pending country and offers both colourings", %{conn: conn} do
    d = doc(conn, "/fr?pays=ETH")
    assert count(d, "#africa-map .map-pending") == 1
    assert count(d, "#map-source-imf[aria-current='true']") == 1
    assert text(d, "[data-field='national-value']") =~ "201,4"
    assert text(d, "[data-field='national-status']") =~ "En cours de vérification"

    d = doc(conn, "/fr?pays=GHA&source=national")
    assert count(d, "#map-source-national[aria-current='true']") == 1

    hidden = d |> LazyHTML.query("[data-field='national-none']") |> LazyHTML.attribute("hidden")
    assert hidden in [[], [nil]]
  end

  test "the country-by-country page lists every country with its source", %{conn: conn} do
    d = doc(conn, "/fr/chiffres-nationaux")
    assert text(d, "h1") =~ "FMI et chiffres nationaux"
    assert count(d, "#national-rows tbody tr") == 54
    assert text(d, "#national-row-ETH") =~ "En cours de vérification"
    assert text(d, "#national-row-GHA") =~ "FMI (repli)"
    assert text(d, "#national-row-ERI") =~ "hors des deux totaux"

    assert conn |> get("/en/national-figures") |> html_response(200) =~ "Sum of national figures"
  end

  test "the admin reviews: verified, the figure counts; rejected, it leaves", %{
    conn: conn,
    admin: admin
  } do
    assert redirected_to(get(conn, "/admin/chiffres-nationaux")) == "/fr/connexion"

    d = doc(admin, "/admin/chiffres-nationaux")
    figure = National.get("ETH", "gdp_usd_bn", 2025)
    assert count(d, "#national-#{figure.id}") == 1
    assert text(d, "#national-#{figure.id}") =~ "Source officielle"
    assert count(d, "#admin-nav-national .admin-cnt") == 1

    admin |> post("/admin/chiffres-nationaux/#{figure.id}/verifier") |> redirected_to()
    assert National.get!(figure.id).status == "verified"
    assert National.africa(National.document(), 2025)["counted"] == 1

    home = doc(build_conn(), "/fr")
    assert text(home, "#national-sum") =~ "1 pays au chiffre officiel"

    admin |> post("/admin/chiffres-nationaux/#{figure.id}/rejeter") |> redirected_to()
    assert National.get!(figure.id).status == "rejected"

    refute text(doc(build_conn(), "/fr/pays/ethiopie/economie"), "#national-card-gdp_usd_bn") =~
             "201,4"
  end
end
