defmodule SyliAtlas.AlertEventsTest do
  use SyliAtlas.DataCase, async: false
  use Oban.Testing, repo: SyliAtlas.Repo, engine: Oban.Engines.Lite

  import Swoosh.TestAssertions
  import SyliAtlas.AccountsFixtures

  alias SyliAtlas.Accounts
  alias SyliAtlas.Accounts.{Alert, AlertDelivery, AlertEvents, AlertRules, Digests, Unsubscribe}
  alias SyliAtlas.Ratings.Review
  alias SyliAtlas.Workers.{AlertEmailWorker, AlertEventWorker, DigestEmailWorker, DigestWorker}

  @today ~D[2026-11-11]
  @monday ~D[2026-11-16]

  setup do
    edition = SyliAtlas.Fixtures.load_snapshot!()
    {:ok, edition: edition}
  end

  defp alert!(user, attrs), do: elem(Accounts.create_alert(user, attrs), 1)

  defp approve_senegal_downgrade do
    {:ok, p} =
      Review.propose(%{
        "country_code" => "SEN",
        "agency" => "moodys",
        "rating" => "C",
        "action_date" => "2026-11-20",
        "action_type" => "downgrade"
      })

    {:ok, rating} =
      Review.approve(p, %{"source_url" => "https://www.moodys.com/research/senegal-downgrade"})

    rating
  end

  describe "rules" do
    test "a threshold fires when crossed, once, from the value last seen" do
      d = &Decimal.new/1
      assert AlertRules.crossed?("indicator_below", d.("5"), d.("14.2"), d.("4.8"))
      assert AlertRules.crossed?("indicator_below", d.("5"), d.("5.1"), d.("5"))
      refute AlertRules.crossed?("indicator_below", d.("5"), d.("4.9"), d.("4.8"))
      refute AlertRules.crossed?("indicator_below", d.("5"), nil, d.("4.8"))
      assert AlertRules.crossed?("indicator_above", d.("75"), d.("72.9"), d.("75.1"))
      refute AlertRules.crossed?("indicator_above", d.("75"), d.("76"), d.("80"))
    end

    test "years of an edition and digest days" do
      assert AlertRules.status(2026, "2026-10") == "projection"
      assert AlertRules.status(2025, "2026-10") == "estimate"
      assert AlertRules.status(2024, "2026-10") == "actual"
      assert AlertRules.digest_day?("weekly", @monday)
      refute AlertRules.digest_day?("weekly", @today)
      assert AlertRules.digest_day?("monthly", ~D[2026-12-01])

      assert AlertRules.digest_period("monthly", ~D[2026-12-01]) ==
               {~D[2026-11-01], ~D[2026-11-30]}
    end
  end

  describe "rating decisions" do
    test "a validated decision alerts followers through Oban, once" do
      member = user_fixture()
      digest_member = user_fixture()
      _other_country = alert!(member, %{"kind" => "rating_change", "area_code" => "CIV"})
      alert = alert!(member, %{"kind" => "rating_change", "area_code" => "SEN"})

      alert!(digest_member, %{
        "kind" => "rating_change",
        "area_code" => "SEN",
        "frequency" => "weekly"
      })

      rating = approve_senegal_downgrade()

      assert_enqueued(
        worker: AlertEventWorker,
        args: %{"type" => "rating", "rating_id" => rating.id}
      )

      assert :ok = perform_job(AlertEventWorker, %{"type" => "rating", "rating_id" => rating.id})

      [immediate] = Repo.all(from d in AlertDelivery, where: d.mode == "immediate")
      assert immediate.alert_id == alert.id
      assert Repo.aggregate(where(AlertDelivery, mode: "digest"), :count) == 1
      assert_enqueued(worker: AlertEmailWorker, args: %{"delivery_id" => immediate.id})

      assert :ok = perform_job(AlertEmailWorker, %{"delivery_id" => immediate.id})

      assert_email_sent(fn email ->
        assert email.subject == "Sénégal : Moody's abaisse la note, C"
        assert email.text_body =~ "https://www.moodys.com/research/senegal-downgrade"
        assert email.html_body =~ ~s(<td align="right">)
        assert email.headers["List-Unsubscribe-Post"] == "List-Unsubscribe=One-Click"
        assert email.headers["List-Unsubscribe"] =~ "/unsubscribe/"
      end)

      # Run twice: no new delivery, no second email.
      assert AlertEvents.on_rating(rating.id) == 0
      assert :ok = perform_job(AlertEmailWorker, %{"delivery_id" => immediate.id})
      refute_email_sent()
      assert Repo.get!(Alert, alert.id).last_triggered_at
    end

    test "a refused validation alerts nobody" do
      alert!(user_fixture(), %{"kind" => "rating_change", "area_code" => "SEN"})

      {:ok, p} =
        Review.propose(%{
          "country_code" => "SEN",
          "agency" => "moodys",
          "rating" => "C",
          "action_date" => "2026-11-20"
        })

      assert {:error, _} = Review.approve(p, %{"source_url" => "https://example.com/news"})
      refute_enqueued(worker: AlertEventWorker)
    end

    test "paused alerts, deactivated members and failed sends" do
      member = user_fixture()
      alert = alert!(member, %{"kind" => "rating_change", "area_code" => "SEN"})
      Accounts.update_alert(alert, %{"active" => false})
      assert AlertEvents.on_rating(approve_senegal_downgrade().id) == 0

      Application.put_env(:syli_atlas, :mail_enabled, false)
      on_exit(fn -> Application.delete_env(:syli_atlas, :mail_enabled) end)
      Accounts.update_alert(Repo.reload(alert), %{"active" => true})

      {:ok, p} =
        Review.propose(%{
          "country_code" => "SEN",
          "agency" => "fitch",
          "rating" => "C",
          "action_date" => "2026-11-21"
        })

      {:ok, rating} =
        Review.approve(p, %{"source_url" => "https://www.fitchratings.com/research/senegal"})

      assert AlertEvents.on_rating(rating.id) == 1
      delivery = Repo.one!(AlertDelivery)

      assert {:cancel, :mail_not_configured} =
               perform_job(AlertEmailWorker, %{"delivery_id" => delivery.id})
    end
  end

  describe "IMF editions" do
    test "a threshold starts from the published value and fires when a new edition crosses it",
         %{edition: edition} do
      member = user_fixture()

      alert =
        alert!(member, %{
          "kind" => "indicator_below",
          "area_code" => "GHA",
          "indicator" => "inflation",
          "threshold" => "5"
        })

      # Ghana, inflation 2026 projected at 4.8 % (IMF, October 2026): already below.
      assert alert.last_value == Decimal.new("4.8")
      assert alert.last_year == 2026
      assert AlertEvents.on_edition(edition.id, today: @today) == 0

      # The value it saw before was above: the edition crosses the threshold.
      Repo.update_all(where(Alert, id: ^alert.id),
        set: [last_value: Decimal.new("14.2"), last_year: 2025]
      )

      assert :ok =
               perform_job(AlertEventWorker, %{
                 "type" => "edition",
                 "edition_id" => edition.id,
                 "today" => "2026-11-11"
               })

      delivery = Repo.one!(AlertDelivery)
      assert delivery.payload["current"] == "4.8"
      assert delivery.payload["previous"] == "14.2"
      assert delivery.payload["status"] == "projection"

      perform_job(AlertEmailWorker, %{"delivery_id" => delivery.id})

      assert_email_sent(fn email ->
        assert email.subject == "Ghana : inflation passe sous 5 %"
        assert email.text_body =~ "Avant (2025) : 14,2 %"
        assert email.text_body =~ "Maintenant (2026) : 4,8 %"
      end)

      # Same edition again: nothing.
      assert AlertEvents.on_edition(edition.id, today: @today) == 0
    end

    test "« new figures » alerts get the country's figures", %{edition: edition} do
      member = user_fixture(%{locale: "en"})
      alert!(member, %{"kind" => "new_edition", "area_code" => "NGA"})
      assert AlertEvents.on_edition(edition.id, today: @today) == 1

      delivery = Repo.one!(AlertDelivery)
      assert delivery.payload["inflation"] == "15.6"
      perform_job(AlertEmailWorker, %{"delivery_id" => delivery.id})
      assert_email_sent(subject: "New IMF figures for Nigeria")
    end

    test "publishing an edition hands it to the alerts", %{edition: edition} do
      perform_job(SyliAtlas.Workers.AfterPublishWorker, %{"edition_id" => edition.id})

      assert_enqueued(
        worker: AlertEventWorker,
        args: %{"type" => "edition", "edition_id" => edition.id}
      )
    end
  end

  describe "digests" do
    test "Monday: figures of followed countries, the week's decisions, alerts kept for it" do
      member = user_fixture()
      Accounts.add_favorite(member, "area", "GHA")
      Accounts.add_favorite(member, "area", "SEN")
      alert!(member, %{"kind" => "rating_change", "area_code" => "SEN", "frequency" => "weekly"})
      AlertEvents.on_rating(approve_senegal_downgrade().id)

      refute member.id in Digests.due_user_ids(@today)
      assert member.id in Digests.due_user_ids(@monday)

      assert :ok = perform_job(DigestWorker, %{"today" => "2026-11-23"})

      assert_enqueued(
        worker: DigestEmailWorker,
        args: %{"user_id" => member.id, "date" => "2026-11-23"}
      )

      assert :ok =
               perform_job(DigestEmailWorker, %{"user_id" => member.id, "date" => "2026-11-23"})

      assert_email_sent(fn email ->
        assert email.subject == "Votre semaine sur Syli Atlas"
        assert email.text_body =~ "Ghana : croissance 5,7 %, inflation 4,8 %"
        assert email.text_body =~ "Sénégal · Moody's : C · abaisse · 2026-11-20"
        assert email.text_body =~ "1 alerte déclenchée"
        assert email.headers["List-Unsubscribe"]
      end)

      assert Repo.one!(AlertDelivery).digested_at
      # Not twice the same day.
      assert :ok = Digests.send(member.id, ~D[2026-11-23])
      refute_email_sent()
    end

    test "nothing to say, no email; digest off still carries the alerts kept for it" do
      quiet = user_fixture()
      assert :ok = Digests.send(quiet.id, @monday)
      refute_email_sent()

      off = user_fixture()
      Accounts.update_preferences(off, %{"digest" => "never"})
      Accounts.add_favorite(off, "area", "GHA")
      refute off.id in Digests.due_user_ids(@monday)

      alert!(off, %{"kind" => "rating_change", "area_code" => "SEN", "frequency" => "weekly"})
      AlertEvents.on_rating(approve_senegal_downgrade().id)
      assert off.id in Digests.due_user_ids(@monday)
      digest = Digests.build(Repo.reload(off), @monday)
      assert digest.figures == []
      assert [_] = digest.deliveries
    end
  end

  describe "unsubscribe" do
    test "tokens stop one alert, the digest, or everything" do
      member = user_fixture()
      alert = alert!(member, %{"kind" => "rating_change", "area_code" => "SEN"})

      assert {:ok, "alert", _} = Unsubscribe.apply(Unsubscribe.token(:alert, alert.id))
      refute Repo.reload(alert).active

      assert {:ok, "digest", _} = Unsubscribe.apply(Unsubscribe.token(:digest, member.id))
      assert Repo.reload(member).digest == "never"

      assert Unsubscribe.apply("forged") == :error
    end
  end
end
