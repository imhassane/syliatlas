defmodule SyliAtlas.Workers.CompaniesWorker do
  @moduledoc """
  Every morning: adds the new companies of `priv/data/companies.json`,
  hides those not confirmed for 90 days, then checks against their source
  the companies never checked or checked more than 30 days ago (at most 25
  a day, so a large list spreads over the month). Also run on demand from
  /admin/entreprises (`%{"id" => id}`: one company).
  """
  use Oban.Worker, queue: :moderation, max_attempts: 2, unique: [period: 600]

  alias SyliAtlas.Companies

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"id" => id}}) do
    id |> Companies.get!() |> Companies.check!()
    :ok
  end

  def perform(_job) do
    seed = Companies.sync_seed!()
    expired = Companies.expire!()
    checked = Companies.due() |> Enum.map(&Companies.check!/1)

    {:ok,
     %{
       added: seed.added,
       changed: seed.changed,
       expired: expired,
       checked: length(checked),
       published: Enum.count(checked, &(&1.status == "published")),
       hidden: Enum.count(checked, &(&1.status == "hidden"))
     }}
  end
end
