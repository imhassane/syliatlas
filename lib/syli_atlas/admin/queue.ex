defmodule SyliAtlas.Admin.Queue do
  @moduledoc """
  What waits for an administrator, file by file: the counters of the admin
  side bar (SyliAtlasWeb.Plugs.AdminShell) and the « À valider » block of
  the daily email (SyliAtlas.Admin.DailyDigest).
  """
  import Ecto.Query

  alias SyliAtlas.Market.QualityIssue
  alias SyliAtlas.Ratings.{Rating, Review}
  alias SyliAtlas.Repo

  @doc """
  The files that wait, for the daily email: one map each with `key`,
  `label`, `count`, `oldest` (when the oldest waiting item arrived, or nil)
  and `path` (the admin page). Files with nothing waiting are left out.
  """
  def items do
    counts = counts()

    [
      {:ratings, "Notations souveraines", "/admin/notations",
       oldest(SyliAtlas.Ratings.Proposal, "pending")},
      {:national, "Chiffres nationaux", "/admin/chiffres-nationaux",
       oldest(SyliAtlas.National.Figure, "pending_review")},
      {:budgets, "Lois de finances", "/admin/budgets",
       oldest(SyliAtlas.Budgets.Proposal, "pending")},
      {:market, "Anomalies de cours", "/admin/marches", oldest(QualityIssue, "open")},
      {:companies, "Entreprises masquées", "/admin/entreprises", nil},
      {:updates, "Tâches en échec (7 jours)", "/admin/mises-a-jour", nil},
      {:emails, "E-mails en échec (7 jours)", "/admin/emails", nil}
    ]
    |> Enum.map(fn {key, label, path, oldest} ->
      %{key: key, label: label, path: path, count: counts[key] || 0, oldest: oldest}
    end)
    |> Enum.filter(&(&1.count > 0))
  end

  defp oldest(schema, status) do
    Repo.one(
      from(r in schema,
        where: r.status == ^status,
        select: type(min(r.inserted_at), :utc_datetime)
      )
    )
  end

  def counts do
    %{
      ratings:
        Review.count_pending() +
          Repo.aggregate(from(r in Rating, where: r.needs_check == true), :count),
      updates: SyliAtlas.Admin.Jobs.failures(7),
      national:
        Repo.aggregate(
          from(f in SyliAtlas.National.Figure, where: f.status == "pending_review"),
          :count
        ),
      market: Repo.aggregate(from(q in QualityIssue, where: q.status == "open"), :count),
      budgets:
        Repo.aggregate(
          from(p in SyliAtlas.Budgets.Proposal, where: p.status == "pending"),
          :count
        ),
      emails: SyliAtlas.Admin.Emails.failures(7),
      social: SyliAtlas.Social.count_drafts(),
      companies:
        Repo.aggregate(
          from(c in SyliAtlas.Companies.Company, where: c.status == "hidden"),
          :count
        )
    }
  end
end
