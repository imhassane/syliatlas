defmodule SyliAtlas.SearchConsoleTest do
  use SyliAtlasWeb.ConnCase, async: false
  alias SyliAtlas.SearchConsole

  setup do
    pem =
      {:rsa, 2048, 65_537}
      |> :public_key.generate_key()
      |> then(&:public_key.pem_entry_encode(:RSAPrivateKey, &1))
      |> List.wrap()
      |> :public_key.pem_encode()

    key =
      Jason.encode!(%{
        "client_email" => "bot@project.iam.gserviceaccount.com",
        "private_key" => pem
      })

    previous = Application.get_env(:syli_atlas, SearchConsole)

    Application.put_env(
      :syli_atlas,
      SearchConsole,
      Keyword.merge(previous, key: Base.encode64(key), site: "sc-domain:syliatlas.com")
    )

    on_exit(fn -> Application.put_env(:syli_atlas, SearchConsole, previous) end)
    :ok
  end

  defp stub(rows_by_dimension) do
    Req.Test.stub(SearchConsole, fn conn ->
      case conn.host do
        "oauth2.googleapis.com" ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          params = URI.decode_query(body)
          [_h, claims, _sig] = String.split(params["assertion"], ".")
          claims = claims |> Base.url_decode64!(padding: false) |> Jason.decode!()
          send(self(), {:claims, claims})
          Req.Test.json(conn, %{"access_token" => "token-1", "expires_in" => 3600})

        "searchconsole.googleapis.com" ->
          assert conn.request_path =~ "sc-domain%3Asyliatlas.com"
          assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer token-1"]
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          dim = Jason.decode!(body)["dimensions"] |> Enum.join("+")
          Req.Test.json(conn, %{"rows" => Map.get(rows_by_dimension, dim, [])})
      end
    end)
  end

  test "a signed service-account token, then every dimension of a day, replaced on re-import" do
    stub(%{
      "query" => [
        %{"keys" => ["sbsw"], "clicks" => 0, "impressions" => 85, "position" => 7.1},
        %{"keys" => ["notation senegal"], "clicks" => 1, "impressions" => 4, "position" => 6.5}
      ],
      "page" => [
        %{
          "keys" => ["https://syliatlas.com/pt/bolsas/jse/ssw"],
          "clicks" => 0,
          "impressions" => 156,
          "position" => 8.2
        },
        %{
          "keys" => ["https://syliatlas.com/ar/debt"],
          "clicks" => 1,
          "impressions" => 10,
          "position" => 5.9
        }
      ],
      "device" => [
        %{"keys" => ["DESKTOP"], "clicks" => 1, "impressions" => 816, "position" => 29.5},
        %{"keys" => ["MOBILE"], "clicks" => 2, "impressions" => 255, "position" => 13.0}
      ],
      "country" => [%{"keys" => ["bra"], "clicks" => 0, "impressions" => 291, "position" => 13.1}],
      "query+page" => [
        %{
          "keys" => ["sbsw", "https://syliatlas.com/pt/bolsas/jse/ssw"],
          "clicks" => 0,
          "impressions" => 80,
          "position" => 7.0
        },
        %{
          "keys" => ["sbsw", "https://syliatlas.com/en/stock-exchanges/jse/ssw"],
          "clicks" => 0,
          "impressions" => 5,
          "position" => 9.0
        }
      ]
    })

    assert {:ok, 9} = SearchConsole.import_days([~D[2026-11-13]])
    assert_received {:claims, %{"iss" => "bot@project.iam.gserviceaccount.com", "scope" => scope}}
    assert scope =~ "webmasters.readonly"

    # The same day again: replaced, not added.
    assert {:ok, 9} = SearchConsole.import_days([~D[2026-11-13]])

    t = SearchConsole.totals(28)
    assert t.clicks == 3 and t.impressions == 1071
    # The page Google shows most for the query, and the handled state.
    assert [%{key: "sbsw", page: "https://syliatlas.com/pt/bolsas/jse/ssw", done: nil}] =
             SearchConsole.opportunities()

    SearchConsole.mark!("sbsw", "admin@example.com", true)
    assert [%{done: %{by: "admin@example.com"}}] = SearchConsole.opportunities()
    SearchConsole.mark!("sbsw", "admin@example.com", false)
    assert [%{done: nil}] = SearchConsole.opportunities()

    assert [%{band: :top3, pages: 0}, %{band: :page1, pages: 2} | _] = SearchConsole.bands()
    assert [%{lang: "pt", section: "bolsas", impressions: 156} | _] = SearchConsole.by_section()

    [pt, ar] = SearchConsole.pages_to_review()
    assert pt.path == "/pt/bolsas/jse/ssw" and is_nil(pt.review)
    SearchConsole.review!("/ar/debt", "Amina")

    assert %{reviewer: "Amina"} =
             Enum.find(SearchConsole.pages_to_review(), &(&1 == ar or &1.path == "/ar/debt")).review
  end

  test "a refused token stops the import" do
    Req.Test.stub(SearchConsole, fn conn ->
      conn
      |> Plug.Conn.put_status(400)
      |> Req.Test.json(%{"error" => "invalid_grant", "error_description" => "Invalid JWT"})
    end)

    assert {:error, {:token, 400, "Invalid JWT"}} = SearchConsole.import_days([~D[2026-11-13]])
  end

  test "the admin pages", %{conn: conn} do
    stub(%{
      "page" => [
        %{
          "keys" => ["https://syliatlas.com/zh/glossary/sovereign-rating"],
          "clicks" => 0,
          "impressions" => 4,
          "position" => 6.5
        }
      ],
      "device" => [%{"keys" => ["MOBILE"], "clicks" => 0, "impressions" => 4, "position" => 6.5}]
    })

    {:ok, _} = SearchConsole.import_days([~D[2026-11-13]])
    admin = SyliAtlas.AccountsFixtures.admin_conn(conn)

    html = admin |> get("/admin/recherche-google") |> html_response(200)
    assert html =~ ~s(id="gsc-stats")
    assert html =~ ~s(id="gsc-brief")
    assert html =~ ~s(id="gsc-chart-svg")
    assert html =~ ~s(id="gsc-where")
    assert html =~ ~s(id="gsc-detail")

    assert admin |> get("/admin/recherche-google?onglet=pages") |> html_response(200) =~
             "gsc-detail-table"

    for tab <- ~w(pages langues appareils pays) do
      assert admin
             |> get("/admin/recherche-google?onglet=#{tab}&mesure=rang&jours=90")
             |> html_response(200) =~
               ~s(id="gsc-chart-svg")
    end

    assert admin
           |> post("/admin/recherche-google/action", %{"query" => "x", "done" => "1"})
           |> redirected_to() =~
             "/admin/recherche-google"

    assert SearchConsole.actions()["x"]
    assert html =~ ~s(id="admin-nav-search_console")

    tr = admin |> get("/admin/traductions") |> html_response(200)
    assert tr =~ "/zh/glossary/sovereign-rating"

    conn2 =
      post(admin, "/admin/traductions/relue", %{
        "path" => "/zh/glossary/sovereign-rating",
        "reviewer" => "Li"
      })

    assert redirected_to(conn2) == "/admin/traductions"
    assert SearchConsole.reviews()["/zh/glossary/sovereign-rating"].reviewer == "Li"
  end
end
