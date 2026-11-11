defmodule SyliAtlas.MarketAlertsTest do
  use SyliAtlas.DataCase, async: false
  use Oban.Testing, repo: SyliAtlas.Repo, engine: Oban.Engines.Lite

  import Swoosh.TestAssertions
  import SyliAtlas.AccountsFixtures

  alias SyliAtlas.Accounts
  alias SyliAtlas.Accounts.{Alert, AlertDelivery, AlertEvents}
  alias SyliAtlas.MarketFixtures, as: F
  alias SyliAtlas.Workers.{AlertEmailWorker, AlertEventWorker}

  setup do
    F.import!()
    :ok
  end

  defp alert!(attrs) do
    {:ok, alert} = Accounts.create_alert(user_fixture(), attrs)
    alert
  end

  test "publishing the market documents hands the session to the alerts" do
    perform_job(SyliAtlas.Workers.MarketPublishWorker, %{})
    assert_enqueued(worker: AlertEventWorker, args: %{"type" => "market"})
  end

  test "a session move beyond the threshold alerts once per session" do
    # Nairobi: −0.78 % in the fixture's session; BRVM +0.10 %. (The JSE's
    # change equals its year-to-date: flagged suspect, so never alerts.)
    nse = alert!(%{"kind" => "session_move", "exchange_code" => "NSE", "threshold" => "0.5"})
    _quiet = alert!(%{"kind" => "session_move", "exchange_code" => "brvm", "threshold" => "1"})
    _suspect = alert!(%{"kind" => "session_move", "exchange_code" => "jse", "threshold" => "1"})
    assert nse.exchange_code == "nse"
    assert nse.area_code == nil

    assert :ok = perform_job(AlertEventWorker, %{"type" => "market"})
    delivery = Repo.one!(AlertDelivery)
    assert delivery.alert_id == nse.id
    assert delivery.payload["change_pct"] =~ "-0.78"

    perform_job(AlertEmailWorker, %{"delivery_id" => delivery.id})

    assert_email_sent(fn email ->
      assert email.subject =~ ": -0,78"
      assert email.subject =~ "sur la séance"
      assert email.text_body =~ "Data by MansaAPI"
      assert email.text_body =~ "pas un conseil en investissement"
      assert email.text_body =~ "/fr/bourses/nse"
    end)

    # Same session published again: nothing new.
    assert AlertEvents.on_market() == 0
  end

  test "a price alert starts from the close and fires when a later close crosses it" do
    # CACI closes at 8 000 XOF in the fixture's session.
    alert =
      alert!(%{
        "kind" => "price_below",
        "exchange_code" => "brvm",
        "ticker" => "caci",
        "threshold" => "8500"
      })

    assert alert.ticker == "CACI"
    assert alert.last_value == Decimal.new("8000")
    assert AlertEvents.on_market() == 0

    Repo.update_all(where(Alert, id: ^alert.id), set: [last_value: Decimal.new("9000")])
    assert AlertEvents.on_market() == 1
    delivery = Repo.one!(AlertDelivery)
    assert delivery.payload["previous"] == "9000"

    perform_job(AlertEmailWorker, %{"delivery_id" => delivery.id})

    assert_email_sent(fn email ->
      assert email.subject =~ "passe sous 8500 XOF"
      assert email.text_body =~ "/fr/bourses/brvm/caci"
    end)
  end

  test "figures flagged by the quality checks never alert" do
    # ECLA: +69.2 % in one session, held by the quality checks.
    alert!(%{
      "kind" => "session_move",
      "exchange_code" => "brvm",
      "ticker" => "ECLA",
      "threshold" => "5"
    })

    assert AlertEvents.on_market() == 0
  end

  test "a market alert needs an exchange and a threshold, a price alert a ticker" do
    member = user_fixture()

    assert {:error, cs} =
             Accounts.create_alert(member, %{
               "kind" => "price_above",
               "exchange_code" => "brvm",
               "threshold" => "10"
             })

    assert errors_on(cs)[:ticker]
    assert {:error, cs} = Accounts.create_alert(member, %{"kind" => "session_move"})
    assert errors_on(cs)[:exchange_code]
    assert errors_on(cs)[:threshold]
  end
end
