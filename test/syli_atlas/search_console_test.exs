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

    key = Jason.encode!(%{"client_email" => "bot@project.iam.gserviceaccount.com", "private_key" => pem})
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
          [dim] = Jason.decode!(body)["dimensions"]
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
        %{"keys" => ["https://syliatlas.com/pt/bolsas/jse/ssw"], "clicks" => 0, "impressions" => 156, "position" => 8.2},
        %{"keys" => ["https://syliatlas.com/ar/debt"], "clicks" => 1, "impressions" => 10, "position" => 5.9}
      ],
      "device" => [
        %{"keys" => ["DESKTOP"], "clicks" => 1, "impressions" => 816, "position" => 29.5},
        %{"keys" => ["MOBILE"], "clicks" => 2, "impressions" => 255, "position" => 13.0}
      ],
      "country" => [%{"keys" => ["bra"], "clicks" => 0, "impressions" => 291, "position" => 13.1}]
    })

    assert {:ok, 7} = SearchConsole.import_days([~D[2026-11-13]])
    assert_received {:claims, %{"iss" => "bot@project.iam.gserviceaccount.com", "scope" => scope}}
    assert scope =~ "webmasters.readonly"

    # The same day again: replaced, not added.
    assert {:ok, 7} = SearchConsole.import_days([~D[2026-11-13]])

    t = SearchConsole.totals(28)
    assert t.clicks == 3 and t.impressions == 1071
    assert [%{key: "sbsw"}] = SearchConsole.opportunities()
    assert [%{lang: "pt", section: "bolsas", impressions: 156} | _] = SearchConsole.by_section()

    [pt, ar] = SearchConsole.pages_to_review()
    assert pt.path == "/pt/bolsas/jse/ssw" and is_nil(pt.review)
    SearchConsole.review!("/ar/debt", "Amina")
    assert %{reviewer: "Amina"} = Enum.find(SearchConsole.pages_to_review(), &(&1 == ar or &1.path == "/ar/debt")).review
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
    stub(%{"page" => [%{"keys" => ["https://syliatlas.com/zh/glossary/sovereign-rating"], "clicks" => 0, "impressions" => 4, "position" => 6.5}],
           "device" => [%{"keys" => ["MOBILE"], "clicks" => 0, "impressions" => 4, "position" => 6.5}]})

    {:ok, _} = SearchConsole.import_days([~D[2026-11-13]])
    admin = SyliAtlas.AccountsFixtures.admin_conn(conn)

    html = admin |> get("/admin/recherche-google") |> html_response(200)
    assert html =~ ~s(id="gsc-stats")
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
