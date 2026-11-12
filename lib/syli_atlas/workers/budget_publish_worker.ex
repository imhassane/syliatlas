defmodule SyliAtlas.Workers.BudgetPublishWorker do
  @moduledoc """
  Rebuilds the budget documents after a law was approved (enqueued in the
  approval's transaction: a refused approval publishes nothing), then lets
  the alerts on that country run.
  """
  use Oban.Worker,
    queue: :budgets,
    max_attempts: 3,
    unique: [keys: [:law_id], period: 60, states: [:available, :scheduled, :retryable]]

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    SyliAtlas.Budgets.rebuild!()

    case args do
      %{"type" => "law", "law_id" => id} ->
        SyliAtlas.Accounts.AlertEvents.budget_law_published(id)

      _ ->
        :ok
    end

    :ok
  end
end
