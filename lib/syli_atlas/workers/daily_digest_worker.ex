defmodule SyliAtlas.Workers.DailyDigestWorker do
  @moduledoc """
  The administrators' daily email (SyliAtlas.Admin.DailyDigest), every
  morning after the watches of the sources, the ratings and the rebasings.
  """
  use Oban.Worker, queue: :alerts, max_attempts: 3, unique: [period: 3600]

  @impl Oban.Worker
  def perform(_job), do: {:ok, SyliAtlas.Admin.DailyDigest.deliver()}
end
