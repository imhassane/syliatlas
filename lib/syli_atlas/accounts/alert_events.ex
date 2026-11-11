defmodule SyliAtlas.Accounts.AlertEvents do
  @moduledoc """
  Alerts react to events, through Oban (queue `alerts`):

    1. an event enqueues `AlertEventWorker` — a rating decision validated in
       the admin (in the same transaction, so a refused validation alerts
       nobody), a new IMF edition published (after `AfterPublishWorker`),
       the market documents rebuilt with a session's closes (after
       `MarketPublishWorker`);
    2. the worker finds the alerts concerned and writes one
       `AlertDelivery` per alert and event (unique: a job run twice never
       emails twice), then enqueues one `AlertEmailWorker` per immediate
       delivery, so a failing email is retried alone;
    3. deliveries of alerts set to « in the digest » wait for
       `SyliAtlas.Accounts.Digests`.
  """
  import Ecto.Query
  require Logger

  alias SyliAtlas.Accounts.{Alert, AlertDelivery, AlertEmails, AlertRules, Emails, User}
  alias SyliAtlas.Ratings.Rating
  alias SyliAtlas.Repo
  alias SyliAtlas.Sources
  alias SyliAtlas.Sources.Observation
  alias SyliAtlas.Workers.{AlertEmailWorker, AlertEventWorker}

  @source "imf_weo"

  # Enqueue ------------------------------------------------------------------

  @doc "A rating decision was published: call inside its transaction."
  def rating_published(%Rating{id: id}),
    do: %{"type" => "rating", "rating_id" => id} |> AlertEventWorker.new() |> Oban.insert!()

  @doc "The market documents were rebuilt (a session's closes)."
  def market_published,
    do: %{"type" => "market"} |> AlertEventWorker.new() |> Oban.insert!()

  @doc "A new IMF edition is online."
  def edition_published(edition_id),
    do:
      %{"type" => "edition", "edition_id" => edition_id}
      |> AlertEventWorker.new()
      |> Oban.insert!()

  # Evaluate -----------------------------------------------------------------

  @doc "Records the deliveries of a rating decision; returns how many were new."
  def on_rating(rating_id) do
    case Repo.get(Rating, rating_id) do
      nil ->
        0

      rating ->
        key = "rating:#{rating.country_code}:#{rating.agency}:#{rating.action_date}"

        payload = %{
          "country_code" => rating.country_code,
          "agency" => rating.agency,
          "rating" => rating.rating,
          "outlook" => rating.outlook,
          "action_date" => rating.action_date,
          "action_type" => rating.action_type,
          "source_url" => rating.source_url
        }

        from(a in active(),
          where: a.kind == "rating_change" and a.area_code == ^rating.country_code
        )
        |> Repo.all()
        |> Enum.count(&record(&1, key, payload))
    end
  end

  @doc """
  Records the deliveries of a new edition: « new figures » alerts, and
  thresholds crossed since the value each alert last saw. Option `:today`.
  """
  def on_edition(edition_id, opts \\ []) do
    edition = Sources.get_edition!(edition_id)
    year = AlertRules.watched_year(Keyword.get_lazy(opts, :today, &Date.utc_today/0))
    alerts = Repo.all(from a in active(), where: a.kind != "rating_change")
    values = values(edition.id, Enum.map(alerts, & &1.area_code), year)
    key = "edition:" <> edition.code

    Enum.count(alerts, fn alert ->
      case alert.kind do
        "new_edition" ->
          record(alert, key, %{
            "country_code" => alert.area_code,
            "edition" => edition.code,
            "edition_label" => edition.label,
            "year" => year,
            "status" => AlertRules.status(year, edition.code),
            "real_gdp_growth" => decimal_string(values[{alert.area_code, "real_gdp_growth"}]),
            "inflation" => decimal_string(values[{alert.area_code, "inflation"}])
          })

        _threshold ->
          threshold(alert, edition, year, key, values[{alert.area_code, alert.indicator}])
      end
    end)
  end

  defp threshold(alert, edition, year, key, current) do
    previous = alert.last_value
    previous_year = alert.last_year

    alert
    |> Ecto.Changeset.change(last_value: current, last_year: year)
    |> Repo.update!()

    AlertRules.crossed?(alert.kind, alert.threshold, previous, current) and
      record(alert, key, %{
        "country_code" => alert.area_code,
        "indicator" => alert.indicator,
        "threshold" => Decimal.to_string(alert.threshold, :normal),
        "previous" => decimal_string(previous),
        "previous_year" => previous_year,
        "current" => decimal_string(current),
        "year" => year,
        "status" => AlertRules.status(year, edition.code),
        "edition" => edition.code,
        "edition_label" => edition.label
      })
  end

  @doc """
  Records the deliveries of a market session: moves beyond a percentage
  (index or security), closes crossing a price. Figures flagged by the
  quality checks (stale, missing, suspect, held) never alert. Nothing
  when the market data may not be shown (`SyliAtlas.Market.public?/0`).
  """
  def on_market do
    if SyliAtlas.Market.public?() do
      Repo.all(from a in active(), where: a.kind in ^Alert.market_kinds())
      |> Enum.group_by(& &1.exchange_code)
      |> Enum.flat_map(fn {code, alerts} ->
        case SyliAtlas.Market.exchange(code) do
          nil -> []
          doc -> Enum.map(alerts, &market(&1, doc))
        end
      end)
      |> Enum.count(& &1)
    else
      0
    end
  end

  defp market(alert, doc) do
    case quote_of(doc, alert.ticker) do
      nil ->
        false

      q ->
        key = "market:#{q.date}"

        payload = %{
          "exchange" => doc["exchange"]["code"],
          "exchange_name" => doc["exchange"]["short_name"],
          "ticker" => q.ticker,
          "name" => q.name,
          "value" => Decimal.to_string(q.value, :normal),
          "change_pct" => q.change_pct && Decimal.to_string(q.change_pct, :normal),
          "currency" => q.currency,
          "date" => q.date,
          "threshold" => Decimal.to_string(alert.threshold, :normal),
          "sources" => doc["sources"]
        }

        case alert.kind do
          "session_move" ->
            q.change_pct != nil and
              not Decimal.lt?(Decimal.abs(q.change_pct), alert.threshold) and
              record(alert, key, payload)

          price ->
            previous = alert.last_value

            alert
            |> Ecto.Changeset.change(last_value: q.value)
            |> Repo.update!()

            kind = if price == "price_above", do: "indicator_above", else: "indicator_below"

            AlertRules.crossed?(kind, alert.threshold, previous, q.value) and
              record(alert, key, Map.put(payload, "previous", decimal_string(previous)))
        end
    end
  end

  # The index (no ticker) or a security, when its figures are sound.
  defp quote_of(doc, nil) do
    index = doc["index"]

    if index["value"] && index["date"] && not flagged?(index["flags"]) do
      %{
        ticker: nil,
        name: doc["exchange"]["index_name"] || doc["exchange"]["short_name"],
        value: Decimal.new(index["value"]),
        change_pct: index["change_pct"] && Decimal.new(index["change_pct"]),
        currency: nil,
        date: index["date"]
      }
    end
  end

  defp quote_of(doc, ticker) do
    row = Enum.find(doc["securities"], &(String.upcase(&1["ticker"]) == ticker))

    if row && row["close"] && row["current"] && not flagged?(row["flags"]) do
      %{
        ticker: row["ticker"],
        name: row["name"],
        value: Decimal.new(row["close"]),
        change_pct: row["change_pct"] && Decimal.new(row["change_pct"]),
        currency: row["currency"],
        date: row["trade_date"]
      }
    end
  end

  defp flagged?(flags),
    do: Enum.any?(~w(missing stale suspect held no_trade), &(flags[&1] == true))

  @doc "The close a new price alert starts from, or nil."
  def market_baseline(exchange_code, ticker) do
    with %{} = doc <- SyliAtlas.Market.exchange(exchange_code),
         %{value: value} <- quote_of(doc, ticker) do
      value
    else
      _ -> nil
    end
  end

  @doc """
  The value a new threshold alert starts from: the published edition's,
  for the watched year. Without it, the first edition only sets it.
  """
  def baseline(area_code, indicator, opts \\ []) do
    year = AlertRules.watched_year(Keyword.get_lazy(opts, :today, &Date.utc_today/0))

    case Sources.published_edition(@source) do
      nil -> {nil, year}
      edition -> {values(edition.id, [area_code], year)[{area_code, indicator}], year}
    end
  end

  # Writes the delivery once; enqueues its email when the alert is immediate.
  defp record(%Alert{} = alert, key, payload) do
    mode = if alert.frequency == "weekly", do: "digest", else: "immediate"
    now = DateTime.utc_now(:second)

    Repo.transaction(fn ->
      {count, rows} =
        Repo.insert_all(
          AlertDelivery,
          [
            %{
              alert_id: alert.id,
              user_id: alert.user_id,
              event_key: key,
              kind: alert.kind,
              payload: payload,
              mode: mode,
              inserted_at: now
            }
          ],
          on_conflict: :nothing,
          conflict_target: [:alert_id, :event_key],
          returning: [:id]
        )

      if count == 1 do
        Repo.update_all(where(Alert, id: ^alert.id), set: [last_triggered_at: now])

        if mode == "immediate",
          do: %{"delivery_id" => hd(rows).id} |> AlertEmailWorker.new() |> Oban.insert!()

        true
      else
        false
      end
    end)
    |> elem(1)
  end

  # Send ---------------------------------------------------------------------

  @doc """
  Sends one immediate delivery. `:ok` when sent or nothing left to send;
  `{:error, _}` to retry; `{:cancel, _}` when email is not configured.
  """
  def send_delivery(delivery_id) do
    delivery =
      Repo.one(
        from d in AlertDelivery,
          where: d.id == ^delivery_id,
          preload: [:alert, :user]
      )

    cond do
      delivery == nil or delivery.sent_at != nil ->
        :ok

      delivery.user.deactivated_at != nil or not delivery.alert.active ->
        :ok

      true ->
        email =
          delivery.user
          |> AlertEmails.alert(delivery)
          |> Swoosh.Email.put_private(:idempotency_key, "alert-delivery-#{delivery.id}")

        case Emails.deliver(email) do
          :ok ->
            Repo.update_all(where(AlertDelivery, id: ^delivery.id),
              set: [sent_at: DateTime.utc_now(:second)]
            )

            :ok

          {:error, :mail_not_configured} ->
            {:cancel, :mail_not_configured}

          {:error, reason} ->
            Logger.warning("alert delivery #{delivery.id} not sent, will retry")
            {:error, reason}
        end
    end
  end

  # Helpers ------------------------------------------------------------------

  defp active do
    from a in Alert,
      join: u in User,
      on: u.id == a.user_id,
      where: a.active and is_nil(u.deactivated_at)
  end

  # %{{area_code, indicator} => Decimal} for one year of an edition.
  defp values(edition_id, area_codes, year) do
    Repo.all(
      from o in Observation,
        where: o.edition_id == ^edition_id and o.year == ^year and o.area_code in ^area_codes,
        select: {o.area_code, o.indicator, o.value}
    )
    |> Map.new(fn {area, indicator, value} ->
      {{area, indicator}, AlertRules.to_decimal(value)}
    end)
  end

  defp decimal_string(nil), do: nil
  defp decimal_string(d), do: Decimal.to_string(d, :normal)
end
