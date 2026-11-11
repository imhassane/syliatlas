defmodule SyliAtlas.AccountsFixtures do
  @moduledoc "Accounts and sessions for tests."

  alias SyliAtlas.Accounts.{Passkey, Sessions, User}
  alias SyliAtlas.Repo

  def user_fixture(attrs \\ %{}) do
    email = attrs[:email] || "member#{System.unique_integer([:positive])}@example.com"
    role = attrs[:role] || "member"
    email |> User.create_changeset(role, attrs[:locale] || "fr") |> Repo.insert!()
  end

  @doc "A passkey row with no real key behind it: enough for the rules on counts."
  def passkey_fixture(user, name \\ "Clé") do
    Repo.insert!(%Passkey{
      user_id: user.id,
      credential_id: :crypto.strong_rand_bytes(16),
      public_key: <<>>,
      name: name
    })
  end

  @doc "A session token of `user`, holding `proofs` (`:code`, `:passkey` or both)."
  def session_token(user, proofs \\ [:code]) do
    first = hd(proofs)
    first_proof = if first == :code, do: :code, else: passkey_fixture(user)
    {token, session} = Sessions.create(user, first_proof)

    if :passkey in proofs and first == :code,
      do: Sessions.record(session, passkey_fixture(user))

    token
  end

  @doc """
  A browser signed in: `conn` carries the session token. Test sessions do
  not survive `recycle/1`: build each request with `as/1`.
  """
  def signed_in(conn, user, proofs \\ [:code]),
    do: as(session_token(user, proofs), conn)

  def as(token, conn \\ Phoenix.ConnTest.build_conn()),
    do: Plug.Test.init_test_session(conn, user_token: token)

  @doc "An administrator past both proofs, at the door of /admin."
  def admin_conn(conn \\ Phoenix.ConnTest.build_conn()) do
    admin =
      user_fixture(%{
        role: "admin",
        email: "admin#{System.unique_integer([:positive])}@example.com"
      })

    signed_in(conn, admin, [:code, :passkey])
  end
end
