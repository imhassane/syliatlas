defmodule SyliAtlasWeb.AccountTest do
  use SyliAtlasWeb.ConnCase, async: false

  import Swoosh.TestAssertions
  import SyliAtlas.AccountsFixtures

  alias SyliAtlas.Accounts
  alias SyliAtlas.SoftAuthenticator

  setup do
    SyliAtlas.Geo.seed_areas!()
    :ok
  end

  defp code_from_email do
    assert_email_sent(fn email ->
      [_, code] = Regex.run(~r/^    (\d{3} \d{3})$/m, email.text_body)
      send(self(), {:code, code})
    end)

    assert_received {:code, code}
    code
  end

  defp sign_in_by_code(conn, email, locale \\ "fr") do
    path = if locale == "en", do: "/en/sign-in", else: "/fr/connexion"
    conn = post(conn, path, %{"email" => email})
    assert redirected_to(conn) == path <> "/code"
    code = code_from_email()
    conn |> recycle() |> post(path <> "/code", %{"code" => code})
  end

  defp json_conn(conn) do
    conn
    |> recycle()
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
  end

  test "the sign-in page offers a passkey and an email code, never indexed", %{conn: conn} do
    html = conn |> get("/fr/connexion") |> html_response(200)
    assert html =~ ~s(id="login-form")
    assert html =~ ~s(data-passkey="sign-in")
    assert html =~ ~s(name="robots" content="noindex")
    assert html =~ ~s(name="csrf-token")

    assert conn |> get("/en/sign-in") |> html_response(200) =~ "Get a code"
  end

  test "a member signs up by code and lands in their space", %{conn: conn} do
    user_fixture(%{role: "admin"})
    conn = sign_in_by_code(conn, "esi@example.com")
    assert redirected_to(conn) == "/fr/mon-espace"

    html = conn |> recycle() |> get("/fr/mon-espace") |> html_response(200)
    assert html =~ ~s(id="favorites-empty")
    assert html =~ "esi@example.com"
    refute html =~ ~s(id="space-admin")
  end

  test "after signing in, the page asked first opens", %{conn: conn} do
    user_fixture(%{role: "admin"})
    conn = get(conn, "/fr/connexion?return_to=%2Ffr%2Fpays%2Fghana")
    conn = sign_in_by_code(recycle(conn), "esi@example.com")
    assert redirected_to(conn) == "/fr/pays/ghana"
    assert_email_sent(subject: "Bienvenue sur Syli Atlas")

    # Never another site.
    conn = get(build_conn(), "/fr/connexion?return_to=%2F%2Fevil.example")
    conn = sign_in_by_code(recycle(conn), "kofi@example.com")
    assert redirected_to(conn) == "/fr/mon-espace"
  end

  test "a wrong code says so; the page keeps the address", %{conn: conn} do
    conn = post(conn, "/fr/connexion", %{"email" => "esi@example.com"})
    _ = code_from_email()

    html =
      conn |> recycle() |> post("/fr/connexion/code", %{"code" => "000000"}) |> html_response(200)

    assert html =~ ~s(id="code-error")
    assert html =~ "esi@example.com"
  end

  test "the first account goes to the passkey step, then to the administration", %{conn: conn} do
    conn = sign_in_by_code(conn, "owner@example.com")
    assert redirected_to(conn) == "/fr/connexion/cle"
    assert_email_sent(subject: "Vous êtes administrateur de Syli Atlas")

    conn = recycle(conn)
    assert redirected_to(get(conn, "/admin/notations")) == "/fr/connexion/cle"

    html = conn |> recycle() |> get("/fr/connexion/cle") |> html_response(200)
    assert html =~ ~s(id="passkey-register")

    key = SoftAuthenticator.new()
    options = conn |> json_conn() |> post("/account/passkeys/options", %{}) |> json_response(200)
    assert options["public_key"]["authenticatorSelection"]["userVerification"] == "required"

    answer =
      conn
      |> json_conn()
      |> post("/account/passkeys", SoftAuthenticator.attestation(key, options))
      |> json_response(200)

    assert answer["redirect"] == "/admin"
    assert_email_sent(subject: "Une clé d'accès a été ajoutée à votre compte")

    assert conn |> recycle() |> get("/admin/notations") |> html_response(200)
  end

  test "an administrator with a passkey confirms it after the code", %{conn: conn} do
    admin = user_fixture(%{role: "admin", email: "owner@example.com"})
    {_t, session} = SyliAtlas.Accounts.Sessions.create(admin, :code)
    key = SoftAuthenticator.new()
    {:ok, options} = Accounts.passkey_registration_options(admin, session)

    {:ok, _, _} =
      Accounts.register_passkey(admin, session, SoftAuthenticator.attestation(key, options))

    conn = sign_in_by_code(conn, "owner@example.com")
    assert redirected_to(conn) == "/fr/connexion/cle"

    assert conn |> recycle() |> get("/fr/connexion/cle") |> html_response(200) =~
             ~s(id="passkey-admin")

    options =
      conn |> json_conn() |> post("/account/admin-proof/options", %{}) |> json_response(200)

    answer =
      conn
      |> json_conn()
      |> post("/account/admin-proof", SoftAuthenticator.assertion(key, options, 1))
      |> json_response(200)

    assert answer["redirect"] == "/admin"
    assert_email_sent(subject: "Connexion à l'administration de Syli Atlas")
    assert conn |> recycle() |> get("/admin/membres") |> html_response(200) =~ "owner@example.com"
  end

  test "a passkey alone signs in, but the administration also wants the code", %{conn: conn} do
    admin = user_fixture(%{role: "admin"})
    {_t, session} = SyliAtlas.Accounts.Sessions.create(admin, :code)
    key = SoftAuthenticator.new()
    {:ok, options} = Accounts.passkey_registration_options(admin, session)

    {:ok, _, _} =
      Accounts.register_passkey(admin, session, SoftAuthenticator.attestation(key, options))

    conn = get(conn, "/fr/connexion")
    options = conn |> json_conn() |> post("/account/passkey/options", %{}) |> json_response(200)

    conn =
      conn
      |> json_conn()
      |> post("/account/passkey", SoftAuthenticator.assertion(key, options, 1))

    assert json_response(conn, 200)["redirect"] == "/fr/mon-espace"
    # recycle/1 keeps the accept header: back to pages.
    conn = conn |> recycle() |> put_req_header("accept", "text/html")
    assert redirected_to(get(conn, "/admin")) == "/fr/connexion/cle"

    assert conn
           |> recycle()
           |> put_req_header("accept", "text/html")
           |> get("/fr/connexion/cle")
           |> html_response(200) =~ ~s(id="admin-key-code")
  end

  test "members never see the administration", %{conn: conn} do
    conn = signed_in(conn, user_fixture(), [:code, :passkey])
    assert conn |> get("/admin/notations") |> html_response(404)
  end

  test "a refused passkey answers 422", %{conn: conn} do
    conn = get(conn, "/fr/connexion")

    assert conn
           |> json_conn()
           |> post("/account/passkey", %{"challenge_id" => "1"})
           |> json_response(422) ==
             %{"error" => "invalid_passkey"}
  end

  test "public pages learn who is signed in from /account/me", %{conn: conn} do
    assert conn |> get("/account/me") |> json_response(200) == %{"signed_in" => false}

    member = user_fixture()
    Accounts.add_favorite(member, "area", "CIV")
    token = session_token(member)
    me = as(token) |> get("/account/me")
    assert get_resp_header(me, "cache-control") == ["private, no-store"]
    body = json_response(me, 200)
    assert body["favorites"] == ["area:CIV"]
    assert body["account"] == "/fr/mon-espace"

    # The star of a public page, with the token /account/me gave.
    # The CSRF token lives in the session cookie /account/me wrote.
    answer =
      me
      |> recycle()
      |> put_req_header("x-csrf-token", body["csrf"])
      |> put_req_header("accept", "application/json")
      |> post("/account/favorites", %{"kind" => "area", "ref" => "GHA"})
      |> json_response(200)

    assert Enum.sort(answer["favorites"]) == ["area:CIV", "area:GHA"]
  end

  test "country pages show the star and the bell, signed out", %{conn: conn} do
    SyliAtlas.Fixtures.load_snapshot!()
    html = conn |> get("/fr/pays/ghana") |> html_response(200)
    assert html =~ ~s(data-favorite="area:GHA")
    assert html =~ "/fr/connexion?return_to=%2Ffr%2Fpays%2Fghana"
    assert html =~ "/fr/mon-espace/alertes?area=GHA"
  end

  test "the space lists favourites and manages alerts", %{conn: conn} do
    member = user_fixture()
    Accounts.add_favorite(member, "area", "GHA")
    token = session_token(member)

    html = as(token, conn) |> get("/fr/mon-espace") |> html_response(200)
    assert html =~ "Ghana"
    assert html =~ "/fr/pays/ghana"

    html = as(token) |> get("/fr/mon-espace/alertes?area=GHA") |> html_response(200)
    assert html =~ ~s(<option value="GHA" selected)

    conn =
      as(token)
      |> post("/account/alerts", %{
        "alert" => %{
          "area_code" => "GHA",
          "kind" => "indicator_below",
          "indicator" => "inflation",
          "threshold" => "5",
          "frequency" => "immediate"
        }
      })

    assert redirected_to(conn) == "/fr/mon-espace/alertes"
    [alert] = Accounts.list_alerts(member)

    html = as(token) |> get("/fr/mon-espace/alertes") |> html_response(200)
    assert html =~ "Inflation (%) sous 5"

    as(token) |> put("/account/alerts/#{alert.id}", %{"active" => "false"})
    refute hd(Accounts.list_alerts(member)).active

    as(token) |> delete("/account/alerts/#{alert.id}")
    assert Accounts.list_alerts(member) == []
  end

  test "security: passkeys, sessions, preferences", %{conn: conn} do
    member = user_fixture()
    token = session_token(member)
    html = as(token, conn) |> get("/fr/mon-espace/securite") |> html_response(200)
    assert html =~ ~s(id="passkey-register")
    assert html =~ ~s(id="sessions")

    conn =
      as(token)
      |> put("/account/preferences", %{
        "preferences" => %{"digest" => "never", "security_emails" => "false", "locale" => "en"}
      })

    assert redirected_to(conn) == "/en/my-space/security"
    member = SyliAtlas.Repo.reload(member)
    assert {member.digest, member.security_emails, member.locale} == {"never", false, "en"}
  end

  test "security: an administrator confirms by email code, then manages every passkey" do
    admin = user_fixture(%{role: "admin"})
    # Signed in by a passkey that no longer works elsewhere: no fresh code.
    token = session_token(admin, [:passkey])
    [broken] = Accounts.list_passkeys(admin)

    html = as(token) |> get("/fr/mon-espace/securite") |> html_response(200)
    assert html =~ ~s(id="passkey-proof")
    assert html =~ ~s(id="security-code-request")
    refute html =~ ~s(id="passkey-register")
    refute html =~ ~s(id="passkey-delete-#{broken.id}")

    # Refused without the code.
    conn = as(token) |> delete("/account/passkeys/#{broken.id}")
    assert redirected_to(conn) == "/fr/mon-espace/securite"
    assert [_] = Accounts.list_passkeys(admin)

    conn = as(token) |> post("/account/security/code")
    code_id = get_session(conn, :security_code)
    code = code_from_email()

    with_code = fn ->
      Plug.Test.init_test_session(build_conn(), user_token: token, security_code: code_id)
    end

    assert with_code.() |> get("/fr/mon-espace/securite") |> html_response(200) =~
             ~s(id="security-code-form")

    conn = with_code.() |> post("/account/security/code/verify", %{"code" => code})
    assert redirected_to(conn) == "/fr/mon-espace/securite"

    html = as(token) |> get("/fr/mon-espace/securite") |> html_response(200)
    refute html =~ ~s(id="passkey-proof")
    assert html =~ ~s(id="passkey-register")
    assert html =~ ~s(id="passkey-rename-#{broken.id}")

    as(token) |> put("/account/passkeys/#{broken.id}", %{"passkey" => %{"name" => "Ancien PC"}})
    assert [%{name: "Ancien PC"}] = Accounts.list_passkeys(admin)

    as(token) |> delete("/account/passkeys/#{broken.id}")
    assert Accounts.list_passkeys(admin) == []
  end

  test "signing out closes the session", %{conn: conn} do
    token = session_token(user_fixture())
    conn = as(token, conn) |> delete("/account/session")
    assert redirected_to(conn) == "/fr"
    assert redirected_to(as(token) |> get("/fr/mon-espace")) == "/fr/connexion"
  end

  test "the administration lists and promotes members", %{conn: _} do
    member = user_fixture(%{email: "kofi@example.com"})
    admin = user_fixture(%{role: "admin"})
    token = session_token(admin, [:code, :passkey])
    html = as(token) |> get("/admin/membres") |> html_response(200)
    assert html =~ "kofi@example.com"

    as(token) |> post("/admin/membres/#{member.id}/role", %{"role" => "admin"})
    assert SyliAtlas.Repo.reload(member).role == "admin"
  end

  test "emails: text and HTML, the button on the right" do
    user = user_fixture(%{locale: "en"})
    email = SyliAtlas.Accounts.Emails.welcome(user)
    assert email.subject == "Welcome to Syli Atlas"
    assert email.text_body =~ "Open my space : http"
    assert email.html_body =~ ~s(<td align="right">)
    assert email.html_body =~ "/en/my-space"
  end

  test "unsubscribe: the page asks, the one-click POST acts without a session", %{conn: conn} do
    member = user_fixture()

    {:ok, alert} =
      Accounts.create_alert(member, %{"kind" => "rating_change", "area_code" => "SEN"})

    token = SyliAtlas.Accounts.Unsubscribe.token(:alert, alert.id)

    html = conn |> get("/unsubscribe/" <> token) |> html_response(200)
    assert html =~ ~s(id="unsubscribe-form")
    assert SyliAtlas.Repo.reload(alert).active

    html = build_conn() |> post("/unsubscribe/" <> token) |> html_response(200)
    assert html =~ ~s(id="unsubscribe-done")
    refute SyliAtlas.Repo.reload(alert).active

    assert build_conn() |> get("/unsubscribe/forged") |> html_response(404) =~ "plus valable"
  end
end
