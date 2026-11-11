defmodule SyliAtlasWeb.RecapControllerTest do
  use SyliAtlasWeb.ConnCase, async: false

  import Swoosh.TestAssertions

  alias SyliAtlas.Recaps
  alias SyliAtlas.Recaps.Subscription

  setup do
    SyliAtlas.Fixtures.load_snapshot!()
    {:ok, email: "lea-#{System.unique_integer([:positive])}@example.org"}
  end

  defp doc(conn, path), do: conn |> get(path) |> html_response(200) |> LazyHTML.from_document()

  defp token_from_email do
    assert_email_sent(fn email ->
      send(self(), {:token, List.last(Regex.run(~r{/recap/confirm/([^\s"<]+)}, email.text_body))})
    end)

    assert_received {:token, token}
    token
  end

  test "the footer offers the recap: a link to its page and the dialog", %{conn: conn} do
    d = doc(conn, "/fr")

    assert LazyHTML.query(d, ~s(#footer-recap a[href="/fr/recap"][data-recap-open]))
           |> Enum.count() == 1

    assert LazyHTML.query(d, ~s(#recap-dialog form[action="/fr/recap"])) |> Enum.count() == 1
    # Every country can be added from the dialog.
    assert LazyHTML.query(d, "#recap-dialog [data-recap-add] option[value]") |> Enum.count() >= 54
    # The footer's brand is the site's logo, and the credit of the market data links to it.
    assert LazyHTML.query(d, ".footer-about .brand svg rect") |> Enum.count() == 4
  end

  test "the page works without JavaScript: a form, then « check your inbox »",
       %{conn: conn, email: email} do
    d = doc(conn, "/fr/recap?pays=civ")
    assert LazyHTML.query(d, ~s(#recap-form input[value="CIV"][checked])) |> Enum.count() == 1
    assert LazyHTML.query(d, "#recap-form input[name='countries[]']") |> Enum.count() == 54

    html =
      build_conn()
      |> post("/fr/recap", %{
        "email" => email,
        "countries" => ["CIV", "SEN"],
        "frequency" => "monthly"
      })
      |> html_response(200)

    assert html =~ ~s(id="recap-sent")
    assert html =~ email

    assert %Subscription{countries: ["CIV", "SEN"], frequency: "monthly", locale: "fr"} =
             SyliAtlas.Repo.get_by(Subscription, email: email)

    assert_email_sent(subject: "Confirmez votre récap Syli Atlas")
  end

  test "the dialog posts JSON; errors come back as JSON too", %{conn: conn, email: email} do
    body =
      conn
      |> put_req_header("accept", "application/json")
      |> post("/en/recap", %{"email" => email, "countries" => ["KEN"]})
      |> json_response(200)

    assert body == %{"ok" => true, "email" => email}
    assert SyliAtlas.Repo.get_by(Subscription, email: email).locale == "en"

    error =
      build_conn()
      |> put_req_header("accept", "application/json")
      |> post("/en/recap", %{"email" => email, "countries" => []})
      |> json_response(422)

    assert error["error"] =~ "Choose between 1 and 10 countries"
  end

  test "the confirmation link asks, then confirms on POST", %{conn: conn, email: email} do
    {:ok, _} = Recaps.subscribe(%{"email" => email, "countries" => ["NGA"], "locale" => "fr"})
    token = token_from_email()

    html = conn |> get("/recap/confirm/" <> token) |> html_response(200)
    assert html =~ ~s(id="recap-confirm-form") and html =~ "Nigeria"
    refute Subscription.confirmed?(SyliAtlas.Repo.get_by(Subscription, email: email))

    html = build_conn() |> post("/recap/confirm/" <> token) |> html_response(200)
    assert html =~ ~s(id="recap-confirmed")
    assert Subscription.confirmed?(SyliAtlas.Repo.get_by(Subscription, email: email))

    assert build_conn() |> get("/recap/confirm/forged") |> html_response(404) =~ "recap-invalid"
  end

  test "the links of a recap change the countries and stop it", %{conn: conn, email: email} do
    {:ok, _} = Recaps.subscribe(%{"email" => email, "countries" => ["NGA"], "locale" => "fr"})
    {:ok, sub} = Recaps.confirm(token_from_email())
    token = Recaps.manage_token(sub)

    d = doc(conn, "/recap/manage/" <> token)

    assert LazyHTML.query(d, ~s(#recap-manage-form input[value="NGA"][checked])) |> Enum.count() ==
             1

    html =
      build_conn()
      |> post("/recap/manage/" <> token, %{
        "countries" => ["GHA", "KEN"],
        "frequency" => "monthly"
      })
      |> html_response(200)

    assert html =~ ~s(id="recap-saved")
    assert %{countries: ["GHA", "KEN"], frequency: "monthly"} = SyliAtlas.Repo.reload(sub)

    assert build_conn()
           |> post("/recap/manage/" <> token, %{"countries" => []})
           |> html_response(422)

    assert build_conn() |> get("/recap/stop/" <> token) |> html_response(200) =~ "recap-stop-form"
    assert SyliAtlas.Repo.reload(sub)

    # The one-click POST of mail clients carries no CSRF token.
    assert build_conn() |> post("/recap/stop/" <> token) |> html_response(200) =~ "recap-stopped"
    refute SyliAtlas.Repo.reload(sub)
    # Opened again: still « stopped », not an error.
    assert build_conn() |> get("/recap/stop/" <> token) |> html_response(200) =~ "recap-stopped"
  end
end
