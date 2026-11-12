defmodule SyliAtlasWeb.Plugs.AdminShell do
  @moduledoc """
  What the admin side bar shows on every admin page: the counters next to
  the menu entries and the admin session (passkey used, closing time).
  Runs after `SyliAtlasWeb.Plugs.AdminAuth`.
  """
  import Plug.Conn
  import Ecto.Query

  alias SyliAtlas.Accounts.{Passkey, Session}
  alias SyliAtlas.Market.QualityIssue
  alias SyliAtlas.Ratings.{Rating, Review}
  alias SyliAtlas.Repo

  def init(opts), do: opts

  def call(%Plug.Conn{halted: true} = conn, _opts), do: conn

  def call(conn, _opts) do
    session = conn.assigns[:current_session]

    conn
    |> assign(:admin_counts, %{
      ratings:
        Review.count_pending() +
          Repo.aggregate(from(r in Rating, where: r.needs_check == true), :count),
      updates: SyliAtlas.Admin.Jobs.failures(7),
      market: Repo.aggregate(from(q in QualityIssue, where: q.status == "open"), :count),
      budgets:
        Repo.aggregate(
          from(p in SyliAtlas.Budgets.Proposal, where: p.status == "pending"),
          :count
        ),
      emails: SyliAtlas.Admin.Emails.failures(7)
    })
    |> assign(:admin_until, session && Session.admin_until(session))
    |> assign(:admin_key, passkey_name(session))
  end

  defp passkey_name(%Session{passkey_id: id}) when not is_nil(id) do
    Repo.one(from p in Passkey, where: p.id == ^id, select: p.name)
  end

  defp passkey_name(_session), do: nil
end
