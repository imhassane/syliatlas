defmodule SyliAtlas.AccountsTest do
  use SyliAtlas.DataCase, async: false

  import Swoosh.TestAssertions
  import SyliAtlas.AccountsFixtures

  alias SyliAtlas.Accounts
  alias SyliAtlas.Accounts.{LoginCode, Session, Sessions}
  alias SyliAtlas.SoftAuthenticator

  # The code is only in the email: read it there, as a person would.
  defp code_from_email do
    assert_email_sent(fn email ->
      [_, code] = Regex.run(~r/^    (\d{3} \d{3})$/m, email.text_body)
      send(self(), {:code, String.replace(code, " ", "")})
    end)

    assert_received {:code, code}
    code
  end

  defp sign_up(email) do
    {:ok, id, email} = Accounts.request_code(email, "fr")
    code = code_from_email()
    {:ok, result} = Accounts.verify_code(id, email, code)
    result
  end

  describe "codes" do
    test "a code by email opens a session; the first account is the administrator" do
      first = sign_up("  Aminata@Example.com ")
      assert first.user.email == "aminata@example.com"
      assert first.user.role == "admin"
      assert first.new_account
      assert first.session.code_verified_at
      assert_email_sent(subject: "Vous êtes administrateur de Syli Atlas")

      second = sign_up("kouadio@example.com")
      assert second.user.role == "member"
      assert_email_sent(subject: "Bienvenue sur Syli Atlas")
    end

    test "an administrator's code email announces the passkey step" do
      user_fixture(%{email: "admin@example.com", role: "admin"})
      {:ok, _id, _} = Accounts.request_code("admin@example.com", "fr")

      assert_email_sent(fn email ->
        assert email.subject =~ "est votre code Syli Atlas"
        assert email.text_body =~ "Compte administrateur"
        assert email.html_body =~ ~s(dir="ltr")
      end)
    end

    test "FIRST_ADMIN_EMAIL keeps the role for that address only" do
      Application.put_env(:syli_atlas, :first_admin_email, "owner@example.com")
      on_exit(fn -> Application.delete_env(:syli_atlas, :first_admin_email) end)

      assert sign_up("someone@example.com").user.role == "member"
      assert_email_sent(subject: "Bienvenue sur Syli Atlas")
      assert sign_up("owner@example.com").user.role == "admin"
    end

    test "a wrong code counts an attempt; five kill the code" do
      {:ok, id, email} = Accounts.request_code("esi@example.com", "fr")
      code = code_from_email()

      for _ <- 1..5,
          do: assert({:error, :invalid_code} = Accounts.verify_code(id, email, "000000"))

      assert {:error, :too_many_attempts} = Accounts.verify_code(id, email, code)
    end

    test "a code works once, for its address, within 10 minutes" do
      {:ok, id, email} = Accounts.request_code("esi@example.com", "fr")
      code = code_from_email()

      assert {:error, :invalid_code} = Accounts.verify_code(id, "other@example.com", code)

      later = DateTime.add(DateTime.utc_now(), LoginCode.ttl_seconds() + 1)
      assert {:error, :expired} = Accounts.verify_code(id, email, code, now: later)

      assert {:ok, _} = Accounts.verify_code(id, email, code)
      assert {:error, :already_used} = Accounts.verify_code(id, email, code)
    end

    test "neither the code nor the address is stored" do
      {:ok, id, _email} = Accounts.request_code("esi@example.com", "fr")
      code = code_from_email()
      row = Repo.get!(LoginCode, id)
      refute row.code_hash =~ code
      refute row.email_hash =~ "esi@example.com"
    end

    test "five codes per address and per hour" do
      for _ <- 1..5, do: assert({:ok, _, _} = Accounts.request_code("x@example.com", "fr"))
      assert {:error, :too_many_codes} = Accounts.request_code("x@example.com", "fr")
      assert {:error, :invalid_email} = Accounts.request_code("not an email", "fr")
    end

    test "without a mail adapter, nothing is sent and no code is kept" do
      Application.put_env(:syli_atlas, :mail_enabled, false)
      on_exit(fn -> Application.delete_env(:syli_atlas, :mail_enabled) end)

      assert {:error, :mail_not_configured} = Accounts.request_code("x@example.com", "fr")
      assert Repo.aggregate(LoginCode, :count) == 0
    end
  end

  describe "passkeys" do
    test "a member adds a passkey, then signs in with it alone" do
      member = user_fixture()
      {_token, session} = Sessions.create(member, :code)
      key = SoftAuthenticator.new()

      {:ok, options} = Accounts.passkey_registration_options(member, session)
      assert options.public_key.authenticatorSelection.userVerification == "preferred"

      {:ok, passkey, _} =
        Accounts.register_passkey(member, session, SoftAuthenticator.attestation(key, options))

      assert passkey.name == "Mon téléphone"

      options = Accounts.passkey_sign_in_options()

      {:ok, %{user: user, session: new_session}} =
        Accounts.passkey_sign_in(SoftAuthenticator.assertion(key, options, 1))

      assert user.id == member.id
      assert new_session.passkey_verified_at
      refute new_session.code_verified_at
    end

    test "a challenge is used once" do
      member = user_fixture()
      {_token, session} = Sessions.create(member, :code)
      key = SoftAuthenticator.new()
      {:ok, options} = Accounts.passkey_registration_options(member, session)

      {:ok, _, _} =
        Accounts.register_passkey(member, session, SoftAuthenticator.attestation(key, options))

      options = Accounts.passkey_sign_in_options()
      answer = SoftAuthenticator.assertion(key, options, 1)
      assert {:ok, _} = Accounts.passkey_sign_in(answer)
      assert {:error, :invalid_passkey} = Accounts.passkey_sign_in(answer)
    end

    test "a counter that does not grow is refused (copied key)" do
      member = user_fixture()
      {_token, session} = Sessions.create(member, :code)
      key = SoftAuthenticator.new()
      {:ok, options} = Accounts.passkey_registration_options(member, session)

      {:ok, _, _} =
        Accounts.register_passkey(member, session, SoftAuthenticator.attestation(key, options))

      assert {:ok, _} =
               Accounts.passkey_sign_in(
                 SoftAuthenticator.assertion(key, Accounts.passkey_sign_in_options(), 5)
               )

      assert {:error, :invalid_passkey} =
               Accounts.passkey_sign_in(
                 SoftAuthenticator.assertion(key, Accounts.passkey_sign_in_options(), 5)
               )
    end

    test "an administrator needs the code and a passkey, in the same session" do
      admin = user_fixture(%{role: "admin"})
      {_token, session} = Sessions.create(admin, :code)
      refute Accounts.admin_session?(admin, session)

      # The first passkey, right after the code: registering is the second proof.
      key = SoftAuthenticator.new()
      {:ok, options} = Accounts.passkey_registration_options(admin, session)
      assert options.public_key.authenticatorSelection.userVerification == "required"

      {:ok, _passkey, session} =
        Accounts.register_passkey(admin, session, SoftAuthenticator.attestation(key, options))

      assert Accounts.admin_session?(admin, session)

      # Next time: code, then the passkey.
      {_token, session} = Sessions.create(admin, :code)
      refute Accounts.admin_session?(admin, session)
      options = Accounts.admin_confirm_options(admin)
      assert [_] = options.public_key.allowCredentials

      {:ok, _, session} =
        Accounts.admin_confirm(admin, session, SoftAuthenticator.assertion(key, options, 1))

      assert Accounts.admin_session?(admin, session)

      # A passkey alone opens a member session, never the administration.
      {:ok, %{session: by_key}} =
        Accounts.passkey_sign_in(
          SoftAuthenticator.assertion(key, Accounts.passkey_sign_in_options(), 2)
        )

      refute Accounts.admin_session?(admin, by_key)

      # Admin rights last 8 hours.
      later = DateTime.add(DateTime.utc_now(), Session.admin_ttl_seconds() + 1)
      refute Session.admin_verified?(session, later)
    end

    test "an administrator's first passkey needs a fresh code" do
      admin = user_fixture(%{role: "admin"})
      {_token, session} = Sessions.create(admin, :code)
      later = DateTime.add(DateTime.utc_now(), 11 * 60)

      assert {:error, :admin_proof_required} =
               Accounts.passkey_registration_options(admin, session, now: later)

      # Signed in by a passkey of someone else? No: by no code at all.
      {_token, keyless} = Sessions.create(admin, passkey_fixture(admin))

      assert {:error, :admin_proof_required} =
               SyliAtlas.Accounts.Passkeys.registration_options(admin, keyless)
    end

    test "another administrator's passkey cannot confirm" do
      admin = user_fixture(%{role: "admin"})
      other = user_fixture(%{role: "admin"})
      {_token, other_session} = Sessions.create(other, :code)
      key = SoftAuthenticator.new()
      {:ok, options} = Accounts.passkey_registration_options(other, other_session)

      {:ok, _, _} =
        Accounts.register_passkey(
          other,
          other_session,
          SoftAuthenticator.attestation(key, options)
        )

      {_token, session} = Sessions.create(admin, :code)
      options = Accounts.admin_confirm_options(admin)

      assert {:error, :invalid_passkey} =
               Accounts.admin_confirm(
                 admin,
                 session,
                 SoftAuthenticator.assertion(key, options, 1)
               )
    end

    test "the last passkey of an administrator stays; removing one closes its sessions" do
      admin = user_fixture(%{role: "admin"})
      only = passkey_fixture(admin)
      assert {:error, :last_admin_passkey} = Accounts.remove_passkey(admin, only.id)

      second = passkey_fixture(admin)
      {token, _session} = Sessions.create(admin, second)
      assert :ok = Accounts.remove_passkey(admin, second.id)
      assert Accounts.fetch_session(token) == nil
    end
  end

  describe "roles" do
    test "the last administrator keeps the role and stays active" do
      admin = user_fixture(%{role: "admin"})
      assert {:error, :last_admin} = Accounts.set_role(admin, "member")
      assert {:error, :last_admin} = Accounts.set_active(admin, false)
      assert {:error, :last_admin} = Accounts.delete_account(admin)

      member = user_fixture()
      assert {:ok, _} = Accounts.set_role(member, "admin")
      assert {:ok, _} = Accounts.set_role(admin, "member")
    end

    test "a deactivated account loses its sessions" do
      member = user_fixture()
      {token, _} = Sessions.create(member, :code)
      {:ok, _} = Accounts.set_active(member, false)
      assert Accounts.fetch_session(token) == nil
    end
  end

  describe "favourites and alerts" do
    test "favourites are added once and removed" do
      member = user_fixture()
      assert :ok = Accounts.add_favorite(member, "area", "CIV")
      assert :ok = Accounts.add_favorite(member, "area", "CIV")
      assert :ok = Accounts.add_favorite(member, "security", "BRVM/SNTS")
      assert {:error, :invalid_favorite} = Accounts.add_favorite(member, "planet", "MARS")
      assert {:error, :invalid_favorite} = Accounts.add_favorite(member, "area", "<script>")
      assert Enum.sort(Accounts.favorite_keys(member)) == ["area:CIV", "security:BRVM/SNTS"]

      assert :ok = Accounts.remove_favorite(member, "area", "CIV")
      assert Accounts.favorite_keys(member) == ["security:BRVM/SNTS"]
    end

    test "a threshold alert needs an indicator and an exact threshold" do
      member = user_fixture()

      assert {:error, changeset} =
               Accounts.create_alert(member, %{"kind" => "indicator_below", "area_code" => "GHA"})

      assert errors_on(changeset)[:indicator]

      {:ok, alert} =
        Accounts.create_alert(member, %{
          "kind" => "indicator_below",
          "area_code" => "GHA",
          "indicator" => "inflation",
          "threshold" => "5.1"
        })

      assert alert.threshold == Decimal.new("5.1")

      {:ok, rating} =
        Accounts.create_alert(member, %{
          "kind" => "rating_change",
          "area_code" => "SEN",
          "threshold" => "3"
        })

      assert rating.threshold == nil
      assert Accounts.Alerts.counts_by_area(member) == %{"GHA" => 1, "SEN" => 1}

      other = user_fixture()
      assert {:error, :not_found} = Accounts.delete_alert(other, alert.id)
      assert {:ok, _} = Accounts.delete_alert(member, alert.id)
    end
  end
end
