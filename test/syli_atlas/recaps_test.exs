defmodule SyliAtlas.RecapsTest do
  use SyliAtlas.DataCase, async: false
  use Oban.Testing, repo: SyliAtlas.Repo, engine: Oban.Engines.Lite

  import Swoosh.TestAssertions

  alias SyliAtlas.Recaps
  alias SyliAtlas.Recaps.{Content, Subscription}
  alias SyliAtlas.Ratings.Review
  alias SyliAtlas.Workers.{RecapEmailWorker, RecapWorker}

  @monday ~D[2026-11-23]

  setup do
    SyliAtlas.Fixtures.load_snapshot!()
    # The rate limits count per address in memory, across tests.
    Process.put(:email, "awa-#{System.unique_integer([:positive])}@example.org")
    :ok
  end

  defp attrs(overrides \\ %{}) do
    Map.merge(
      %{
        "email" => "  " <> String.upcase(Process.get(:email), :ascii) <> " ",
        "countries" => ["SEN", "civ", "SEN"],
        "frequency" => "weekly",
        "locale" => "fr"
      },
      overrides
    )
  end

  # The confirmation link of the last email sent.
  defp confirm_token do
    assert_email_sent(fn email ->
      [_, token] = Regex.run(~r{/recap/confirm/([^\s"<]+)}, email.text_body)
      send(self(), {:token, token})
    end)

    receive do
      {:token, token} -> token
    end
  end

  defp subscribed!(overrides \\ %{}) do
    {:ok, _pending} = Recaps.subscribe(attrs(overrides))
    {:ok, sub} = Recaps.confirm(confirm_token())
    sub
  end

  describe "subscribing" do
    test "stores the address unconfirmed and sends one confirmation email" do
      assert {:ok, sub} = Recaps.subscribe(attrs())
      assert sub.email == Process.get(:email)
      assert sub.countries == ["SEN", "CIV"]
      refute Subscription.confirmed?(sub)

      assert_email_sent(fn email ->
        assert email.to == [{"", Process.get(:email)}]
        assert email.subject == "Confirmez votre récap Syli Atlas"
        assert email.text_body =~ "Pays : Sénégal, Côte d'Ivoire"
        assert email.text_body =~ "Fréquence : chaque lundi"
        assert email.text_body =~ "/recap/confirm/"
      end)
    end

    test "refuses a bad address, no country, too many or unknown countries" do
      assert {:error, %Ecto.Changeset{}} = Recaps.subscribe(attrs(%{"email" => "awa"}))
      assert {:error, %Ecto.Changeset{}} = Recaps.subscribe(attrs(%{"countries" => []}))
      assert {:error, %Ecto.Changeset{}} = Recaps.subscribe(attrs(%{"countries" => ["XXX"]}))

      eleven = ~w(SEN CIV NGA KEN GHA MAR EGY ZAF ETH DZA TUN)
      assert {:error, %Ecto.Changeset{}} = Recaps.subscribe(attrs(%{"countries" => eleven}))
      assert Repo.aggregate(Subscription, :count) == 0
      refute_email_sent()
    end

    test "at most 3 confirmation emails per address and per hour" do
      email = "limit-#{System.unique_integer([:positive])}@example.org"
      for _ <- 1..3, do: assert({:ok, _} = Recaps.subscribe(attrs(%{"email" => email})))
      assert {:error, :rate_limited} = Recaps.subscribe(attrs(%{"email" => email}))
    end

    test "the link confirms once, with the choices it carries" do
      {:ok, _} = Recaps.subscribe(attrs())
      token = confirm_token()

      assert {:ok, sub} = Recaps.confirm(token)
      assert Subscription.confirmed?(sub)
      at = sub.confirmed_at
      assert {:ok, again} = Recaps.confirm(token)
      assert again.confirmed_at == at
      assert Recaps.confirm("forged") == :error
    end

    test "a new request on a confirmed address changes nothing until its link is used" do
      sub = subscribed!()

      assert {:ok, _} =
               Recaps.subscribe(attrs(%{"countries" => ["KEN"], "frequency" => "monthly"}))

      assert_email_sent(fn email ->
        assert email.text_body =~ "reçoit déjà le récap"
        assert email.text_body =~ "Pays : Kenya"

        send(
          self(),
          {:token, Regex.run(~r{/recap/confirm/([^\s"<]+)}, email.text_body) |> List.last()}
        )
      end)

      assert Repo.reload(sub).countries == ["SEN", "CIV"]
      assert_received {:token, token}
      {:ok, _} = Recaps.confirm(token)
      assert %{countries: ["KEN"], frequency: "monthly"} = Repo.reload(sub)
    end

    test "addresses never confirmed are deleted after 7 days" do
      {:ok, sub} = Recaps.subscribe(attrs())
      assert_email_sent()

      confirmed =
        subscribed!(%{"email" => "kofi-#{System.unique_integer([:positive])}@example.org"})

      assert Recaps.purge_unconfirmed(DateTime.add(DateTime.utc_now(), 6 * 86_400)) == 0
      assert Recaps.purge_unconfirmed(DateTime.add(DateTime.utc_now(), 8 * 86_400)) == 1
      refute Repo.reload(sub)
      assert Repo.reload(confirmed)
    end
  end

  describe "managing" do
    test "the change link updates the countries; the stop link deletes the row" do
      sub = subscribed!()
      token = Recaps.manage_token(sub)

      assert {:ok, ^sub} = Recaps.resolve_manage(token)

      assert {:ok, updated} =
               Recaps.update(sub, %{"countries" => ["NGA"], "frequency" => "monthly"})

      assert updated.countries == ["NGA"] and updated.frequency == "monthly"
      assert {:error, _} = Recaps.update(updated, %{"countries" => []})

      assert {:ok, "fr"} = Recaps.unsubscribe(token)
      refute Repo.reload(sub)
      assert {:ok, nil} = Recaps.unsubscribe(token)
      assert Recaps.unsubscribe("forged") == :error
    end
  end

  describe "sending" do
    test "Monday: one email per confirmed address, the decisions of the week first" do
      sub = subscribed!()

      {:ok, _unconfirmed} =
        Recaps.subscribe(
          attrs(%{"email" => "pending-#{System.unique_integer([:positive])}@example.org"})
        )

      assert_email_sent()

      {:ok, p} =
        Review.propose(%{
          "country_code" => "CIV",
          "agency" => "moodys",
          "rating" => "Ba1",
          "outlook" => "stable",
          "action_date" => "2026-11-18",
          "action_type" => "upgrade"
        })

      {:ok, _} = Review.approve(p, %{"source_url" => "https://www.moodys.com/research/civ"})

      assert Recaps.due_ids(~D[2026-11-24]) == []
      assert Recaps.due_ids(@monday) == [sub.id]

      assert :ok = perform_job(RecapWorker, %{"today" => Date.to_iso8601(@monday)})

      assert_enqueued(
        worker: RecapEmailWorker,
        args: %{"subscription_id" => sub.id, "date" => "2026-11-23"}
      )

      assert :ok =
               perform_job(RecapEmailWorker, %{
                 "subscription_id" => sub.id,
                 "date" => "2026-11-23"
               })

      assert_email_sent(fn email ->
        assert email.subject == "Côte d'Ivoire, Sénégal : votre semaine"
        body = email.text_body
        assert body =~ "Vos 2 pays cette semaine"
        assert body =~ "Notations : 1 décision · Côte d'Ivoire"
        # The country with news comes first.
        assert :binary.match(body, "## Côte d'Ivoire") < :binary.match(body, "## Sénégal")
        assert body =~ "Moody's relève sa note : Ba1, perspective stable · 18/11/2026"
        assert body =~ "parité fixe : 1 EUR = 655,957 XOF"
        assert body =~ "Repères FMI, 2026"
        assert body =~ "Croissance : "
        assert body =~ "Modifier mes pays : http"
        assert body =~ "Information, pas un conseil en investissement."
        assert email.headers["List-Unsubscribe"] =~ "/recap/stop/"
      end)

      # Not twice the same day.
      assert :ok = Recaps.send(sub.id, @monday)
      refute_email_sent()
      assert Recaps.due_ids(@monday) == []
    end

    test "an unconfirmed address gets nothing but its confirmation" do
      {:ok, sub} = Recaps.subscribe(attrs())
      assert_email_sent()
      assert :ok = Recaps.send(sub.id, @monday)
      refute_email_sent()
    end
  end

  describe "the exchange of a country" do
    @exchange %{"code" => "BRVM", "short_name" => "BRVM", "index_name" => "BRVM Composite"}

    defp doc(history, flags \\ %{}),
      do: %{
        "history" => history,
        "index" => %{"flags" => flags},
        "sources" => [%{"code" => "mansa"}]
      }

    test "the change from the last close before the period to the last close in it" do
      history = [["2026-11-13", "300"], ["2026-11-14", "310"], ["2026-11-20", "325.5"]]
      move = Content.index_move(@exchange, doc(history), ~D[2026-11-16], ~D[2026-11-22])
      assert move.change_pct == 5.0
      assert move.date == "2026-11-20"
      assert move.sources == ["mansa"]
    end

    test "nothing when the index is flagged, or has no close in the period" do
      history = [["2026-11-14", "310"], ["2026-11-20", "325"]]

      refute Content.index_move(
               @exchange,
               doc(history, %{"stale" => true}),
               ~D[2026-11-16],
               ~D[2026-11-22]
             )

      refute Content.index_move(
               @exchange,
               doc([["2026-11-14", "310"]]),
               ~D[2026-11-16],
               ~D[2026-11-22]
             )

      refute Content.index_move(@exchange, nil, ~D[2026-11-16], ~D[2026-11-22])
    end
  end
end
