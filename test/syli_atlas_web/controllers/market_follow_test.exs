defmodule SyliAtlasWeb.MarketFollowTest do
  use SyliAtlasWeb.ConnCase, async: false

  import SyliAtlas.AccountsFixtures

  setup do
    SyliAtlas.MarketFixtures.import!()
    :ok
  end

  test "exchange and security pages carry the star and the bell", %{conn: conn} do
    html = conn |> get("/fr/bourses/brvm") |> html_response(200)
    assert html =~ ~s(data-favorite="exchange:brvm")
    assert html =~ "/fr/mon-espace/alertes?exchange=brvm#market-alert"

    html = build_conn() |> get("/fr/bourses/brvm/caci") |> html_response(200)
    assert html =~ ~s(data-favorite="security:brvm/CACI")
    assert html =~ "exchange=brvm&amp;ticker=CACI#market-alert"
  end

  test "the bell opens the market alert form filled in, which creates the alert", %{conn: _} do
    member = user_fixture()
    token = session_token(member)

    html =
      as(token) |> get("/fr/mon-espace/alertes?exchange=brvm&ticker=CACI") |> html_response(200)

    assert html =~ ~s(id="market-alert-form")
    [select] = Regex.run(~r/<select[^>]*id="market-exchange".*?<\/select>/s, html)
    assert select =~ ~s(<option value="brvm" selected)
    assert html =~ ~s(value="CACI")

    conn =
      as(token)
      |> post("/account/alerts", %{
        "alert" => %{
          "kind" => "price_below",
          "exchange_code" => "brvm",
          "ticker" => "CACI",
          "threshold" => "7500",
          "frequency" => "immediate"
        }
      })

    assert redirected_to(conn) == "/fr/mon-espace/alertes"
    html = as(token) |> get("/fr/mon-espace/alertes") |> html_response(200)
    assert html =~ "CACI · BRVM"
    assert html =~ "clôture sous 7500"
  end
end
