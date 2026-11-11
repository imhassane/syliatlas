defmodule SyliAtlas.Market.Consolidation do
  @moduledoc """
  Picks, for each security or index and session, the one value published:
  the observation of the best-ranked source for that exchange (see
  `SyliAtlas.Market.Reference.ranked_sources/3`), unless a check holds it.
  The published row keeps the id of its observation, hence its source, its
  raw payload and its parser version.
  """
  import Ecto.Query
  alias SyliAtlas.Repo
  alias SyliAtlas.Market.{EodPrice, IndexValue, Observation, Quality, Reference, Security}

  def consolidate_security!(security_id, trade_date) do
    security = Repo.get!(Security, security_id)

    with %Observation{} = obs <-
           pick("security", security_id, trade_date, security.exchange_id, "prices"),
         false <- Quality.held?("security", security_id, trade_date) do
      Repo.insert!(
        %EodPrice{
          security_id: security_id,
          trade_date: trade_date,
          close: obs.close,
          change: obs.change,
          change_pct: obs.change_pct,
          volume: obs.volume,
          currency: obs.currency || security.currency,
          source: obs.source,
          observation_id: obs.id,
          as_of: obs.as_of,
          consolidated_at: now()
        },
        on_conflict: {:replace_all_except, [:security_id, :trade_date]},
        conflict_target: [:security_id, :trade_date]
      )

      :published
    else
      _ -> :skipped
    end
  end

  def consolidate_index!(exchange_id, trade_date) do
    case pick("index", exchange_id, trade_date, exchange_id, "indices") do
      %Observation{} = obs ->
        Repo.insert!(
          %IndexValue{
            exchange_id: exchange_id,
            trade_date: trade_date,
            value: obs.close,
            change_pct: obs.change_pct,
            ytd_pct: obs.ytd_pct || ytd_from_same_source(obs),
            source: obs.source,
            observation_id: obs.id,
            as_of: obs.as_of,
            consolidated_at: now()
          },
          on_conflict: {:replace_all_except, [:exchange_id, :trade_date]},
          conflict_target: [:exchange_id, :trade_date]
        )

        :published

      nil ->
        :skipped
    end
  end

  # The latest observation of the best-ranked source that has one.
  defp pick(subject_type, subject_id, trade_date, exchange_id, dataset) do
    observations =
      Repo.all(
        from o in Observation,
          where:
            o.subject_type == ^subject_type and o.subject_id == ^subject_id and
              o.trade_date == ^trade_date,
          order_by: [desc: o.ingested_at, desc: o.id]
      )

    exchange_id
    |> Reference.ranked_sources(dataset, trade_date)
    |> Enum.find_value(fn source -> Enum.find(observations, &(&1.source == source)) end)
  end

  # The daily list of exchanges gives no change since 1 January; the list of
  # indices does. Both come from the same source on the same day.
  defp ytd_from_same_source(%Observation{} = obs) do
    Repo.one(
      from o in Observation,
        where:
          o.subject_type == "index" and o.subject_id == ^obs.subject_id and
            o.trade_date == ^obs.trade_date and o.source == ^obs.source and
            not is_nil(o.ytd_pct),
        order_by: [desc: o.ingested_at],
        limit: 1,
        select: o.ytd_pct
    )
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
