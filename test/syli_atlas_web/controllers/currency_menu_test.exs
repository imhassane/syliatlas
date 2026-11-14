defmodule SyliAtlasWeb.CurrencyMenuTest do
  use SyliAtlasWeb.ConnCase, async: false

  alias SyliAtlas.Fx
  alias SyliAtlas.Fx.Rate
  alias SyliAtlas.FxFixtures, as: F
  alias SyliAtlas.Repo
  alias SyliAtlasWeb.VisitorController

  defp doc(conn, path), do: conn |> get(path) |> html_response(200) |> LazyHTML.from_document()
  defp count(html, sel), do: html |> LazyHTML.query(sel) |> Enum.count()

  test "the visitor's country gives the default currency, as for the language", %{conn: conn} do
    assert VisitorController.currency_for("CI") == "XOF"
    assert VisitorController.currency_for("NG") == "NGN"
    assert VisitorController.currency_for("CM") == "XAF"
    assert VisitorController.currency_for("FR") == "EUR"
    assert VisitorController.currency_for("US") == "USD"
    assert VisitorController.currency_for("CN") == "CNY"
    assert VisitorController.currency_for("BR") == nil

    conn = conn |> put_req_header("cf-ipcountry", "ke") |> get("/visitor")
    assert json_response(conn, 200) == %{"country" => "KE", "currency" => "KES"}
    assert get_resp_header(conn, "cache-control") == ["private, no-store"]

    assert json_response(get(build_conn(), "/visitor"), 200) == %{
             "country" => nil,
             "currency" => nil
           }
  end

  test "yearly averages: one per currency and year, with the fixed parities" do
    for {day, i} <- Enum.with_index(Date.range(~D[2025-03-01], ~D[2025-03-25])) do
      for {code, rate} <- [{"NGN", 1500 + i}, {"EUR", "0.9"}] do
        Repo.insert!(%Rate{
          currency: code,
          date: day,
          source: "exchange_api",
          rate: Decimal.new("#{rate}"),
          inserted_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
      end
    end

    # Ten days only: too few for an average.
    for day <- Date.range(~D[2024-05-01], ~D[2024-05-10]) do
      Repo.insert!(%Rate{
        currency: "NGN",
        date: day,
        source: "exchange_api",
        rate: Decimal.new(1400),
        inserted_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
    end

    years = Fx.year_averages()
    assert Map.keys(years) == ["2025"]
    assert_in_delta String.to_float(years["2025"]["NGN"]), 1512.0, 1.0e-6
    # The CFA franc follows the euro's average exactly.
    assert_in_delta String.to_float(years["2025"]["XOF"]), 0.9 * 655.957, 1.0e-4
  end

  describe "with rates" do
    setup do
      SyliAtlas.Fixtures.load_snapshot!()
      F.import!()
      :ok
    end

    test "the header carries the menu, hidden until the script runs, with the rates", %{
      conn: conn
    } do
      html = doc(conn, "/fr/monnaies")
      assert count(html, "#currency-menu[hidden][data-currency-menu]") == 1
      # Auto, original currencies, the 3 references and 42 African currencies.
      assert count(html, "#currency-menu-list [role=option]") == 2 + 45
      assert count(html, ~s(#currency-menu-auto[aria-selected="true"])) == 1

      rates =
        html
        |> LazyHTML.query("#currency-menu script[data-money-rates]")
        |> LazyHTML.text()
        |> Jason.decode!()

      assert rates["as_of"] == "2026-11-11"
      assert Map.has_key?(rates, "years")
      assert rates["rates"]["NGN"]
    end

    test "a country's GDP is an amount the menu can rewrite, at the rate of its year", %{
      conn: conn
    } do
      html = doc(conn, "/fr/pays/nigeria")
      [gdp] = html |> LazyHTML.query("#kpi-gdp .money") |> Enum.to_list()
      assert LazyHTML.attribute(gdp, "data-currency") == ["USD"]
      assert [year] = LazyHTML.attribute(gdp, "data-year")
      assert String.match?(year, ~r/^\d{4}$/)
      assert [value] = LazyHTML.attribute(gdp, "data-money")
      assert String.to_float(value) > 1.0e10
    end
  end
end
