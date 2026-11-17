defmodule SyliAtlas.SocialTest do
  use SyliAtlas.DataCase, async: false
  use Oban.Testing, repo: SyliAtlas.Repo, engine: Oban.Engines.Lite

  alias SyliAtlas.Ratings.Rating
  alias SyliAtlas.Repo
  alias SyliAtlas.Social
  alias SyliAtlas.Social.{Buffer, Drafts, Post}
  alias SyliAtlas.Workers.SocialPublishWorker

  setup do
    SyliAtlas.Geo.seed_areas!()
    :ok
  end

  defp rating!(attrs) do
    %Rating{}
    |> Rating.changeset(
      Map.merge(
        %{country_code: "ZMB", agency: "moodys", outlook: "stable", action_type: "affirmed"},
        attrs
      )
    )
    |> Repo.insert!()
  end

  describe "drafts from a rating decision" do
    test "an upgrade prepares one post per network, from the previous rating" do
      rating!(%{rating: "Caa2", action_date: "2025-03-01"})

      r =
        rating!(%{
          rating: "Caa1",
          outlook: "positive",
          action_date: "2026-10-30",
          action_type: "upgrade"
        })

      assert {:ok, %Post{} = post} = Drafts.on_rating(r.id)
      assert post.key == "rating:ZMB:moodys:2026-10-30"
      assert post.text_x =~ "Moody's upgrades Zambia to Caa1 (from Caa2), outlook positive."
      assert post.text_linkedin =~ "Moody's relève la note de la Zambie : Caa2 → Caa1"
      assert post.text_linkedin =~ "(30 oct. 2026)"
      assert post.link_x =~ "/en/credit-ratings/zambia?utm_source=x&utm_medium=social"
      assert post.link_linkedin =~ "utm_source=linkedin"
      assert post.image_url =~ "/fr/notations/zambie"
      assert post.image_url_x =~ "/en/credit-ratings/zambia"
      assert Post.x_length(post) <= Post.x_limit()

      # The same event twice: still one draft.
      assert Drafts.on_rating(r.id) == :exists
      assert Social.count_drafts() == 1
    end

    test "the alert job of a rating decision prepares the draft too" do
      rating!(%{rating: "Caa2", action_date: "2025-03-01"})
      r = rating!(%{rating: "Caa3", action_date: "2026-11-02", action_type: "downgrade"})

      :ok =
        perform_job(SyliAtlas.Workers.AlertEventWorker, %{"type" => "rating", "rating_id" => r.id})

      assert [%Post{text_x: "Moody's downgrades Zambia to Caa3 (from Caa2)" <> _}] =
               Social.drafts()
    end

    test "a recent change checked by hand prepares its post, an old one does not" do
      recent =
        rating!(%{
          rating: "B-",
          outlook: "positive",
          action_type: "upgrade",
          action_date: Date.utc_today() |> Date.add(-10) |> Date.to_iso8601(),
          country_code: "BFA",
          agency: "sp",
          needs_check: true
        })

      old =
        rating!(%{
          rating: "Caa1",
          action_type: "upgrade",
          action_date: "2025-01-10",
          needs_check: true
        })

      # Still to check: not offered yet.
      assert Drafts.rating_candidates() == []

      {:ok, _} =
        SyliAtlas.Ratings.Review.mark_checked(recent, %{
          "source_url" => "https://disclosure.spglobal.com/ratings/en/x"
        })

      {:ok, _} =
        SyliAtlas.Ratings.Review.mark_checked(old, %{
          "source_url" => "https://ratings.moodys.com/x"
        })

      assert [%Post{key: "rating:BFA:sp:" <> _, text_x: "S&P upgrades Burkina Faso to B-" <> _}] =
               Social.drafts()

      assert Drafts.rating_candidates() == []
    end

    test "an affirmation prepares nothing" do
      r = rating!(%{rating: "B", action_date: "2026-10-08", country_code: "EGY", agency: "fitch"})
      assert Drafts.on_rating(r.id) == :skip
      assert Social.count_drafts() == 0
    end

    test "a builder that raises never reaches the caller" do
      assert Drafts.safely(fn -> raise "boom" end) == :error
    end
  end

  describe "budget laws" do
    test "a voted law, once; a tabled one, never" do
      law = %{
        country_code: "SEN",
        fiscal_year: 2027,
        kind: "initial",
        sequence: 1,
        stage: "voted",
        expenditure: Decimal.new("7346000000000"),
        currency: "XOF",
        source_name: "Assemblée nationale"
      }

      assert {:ok, attrs} = Drafts.budget_law(law)

      assert attrs.text_x =~
               "Senegal's 2027 budget is voted: 7,346 billion CFA francs of spending."

      assert attrs.text_linkedin =~
               "Le Sénégal a voté sa loi de finances 2027 : 7 346 milliards de francs CFA de dépenses."

      assert attrs.link_x =~ "/en/countries/senegal/budget"
      assert Drafts.budget_law(%{law | stage: "tabled"}) == :skip
    end

    test "with exchange rates, the amount in dollars follows in parentheses" do
      SyliAtlas.FxFixtures.import!()

      {:ok, attrs} =
        Drafts.budget_law(%{
          country_code: "SEN",
          fiscal_year: 2027,
          kind: "initial",
          sequence: 1,
          stage: "voted",
          expenditure: Decimal.new("7346000000000"),
          currency: "XOF",
          source_name: nil
        })

      # 7 346 billion XOF at 587.66 per dollar.
      assert attrs.text_x =~ "7,346 billion CFA francs (about $12.5 billion) of spending"

      assert attrs.text_linkedin =~
               "7 346 milliards de francs CFA (environ 12,5 milliards de dollars)"
    end
  end

  describe "approval and sending (simulated)" do
    setup do
      {:ok, post} =
        Social.create_draft(%{
          key: "edition:1",
          kind: "edition",
          text_x: "New IMF forecasts",
          text_linkedin: "Le FMI publie ses prévisions.",
          link_x: "https://syliatlas.com/en/x?utm_source=x",
          link_linkedin: "https://syliatlas.com/fr/x?utm_source=linkedin"
        })

      {:ok, post: post}
    end

    test "approved for both networks, sent by the job, marked simulated", %{post: post} do
      assert {:ok, post} = Social.approve(post, ["x", "linkedin"], %{}, "admin@test")
      assert post.status == "approved"
      assert_enqueued(worker: SocialPublishWorker, args: %{"post_id" => post.id})

      assert :ok = perform_job(SocialPublishWorker, %{"post_id" => post.id})
      post = Social.get!(post.id)
      assert post.status == "done"
      assert post.x_state == "simulated"
      assert post.linkedin_state == "simulated"
      assert post.sent_at
    end

    test "X's image is the English page's, even for drafts written before" do
      old = %Post{
        link_x: "https://syliatlas.com/en/credit-ratings/zambia?utm_source=x",
        image_url: "fr.png"
      }

      assert Post.x_image(old) =~ ~r{/og/[^/]+/en/credit-ratings/zambia\.png$}
      assert Post.x_image(%{old | image_url_x: "en.png"}) == "en.png"
    end

    test "LinkedIn gets the link at the end, old wording reworded" do
      post = %Post{
        text_linkedin: "Le classement : lien en premier commentaire.",
        link_linkedin: "https://syliatlas.com/fr/x"
      }

      assert Post.linkedin_body(post) ==
               "Le classement : lien ci-dessous.\nhttps://syliatlas.com/fr/x"
    end

    test "a network can be sent again: after a failure or a deletion in Buffer", %{post: post} do
      {:ok, post} = Social.approve(post, ["x", "linkedin"], %{}, "admin@test")
      :ok = perform_job(SocialPublishWorker, %{"post_id" => post.id})
      post = Social.get!(post.id)
      assert post.status == "done"

      # Deleted in Buffer: sent again on X only.
      assert {:ok, post} = Social.resend(post, "x")
      assert post.status == "approved" and post.x_state == "pending" and post.x_ref == nil
      assert post.linkedin_state == "simulated"
      :ok = perform_job(SocialPublishWorker, %{"post_id" => post.id})
      post = Social.get!(post.id)
      assert post.status == "done" and post.x_state == "simulated"

      # A failure.
      post =
        post
        |> Ecto.Changeset.change(linkedin_state: "failed", linkedin_error: "refused")
        |> Repo.update!()

      assert {:ok, _} = Social.resend(post, "linkedin")
      assert Social.resend(%{post | status: "draft"}, "x") == {:error, :nothing_to_resend}
    end

    test "only X: LinkedIn stays untouched", %{post: post} do
      {:ok, post} = Social.approve(post, ["x"], %{}, "admin@test")
      :ok = perform_job(SocialPublishWorker, %{"post_id" => post.id})
      post = Social.get!(post.id)
      assert post.x_state == "simulated"
      assert post.linkedin_state == nil
    end

    test "edited texts are kept, too long for X is refused", %{post: post} do
      assert {:error, %Ecto.Changeset{}} =
               Social.update_texts(post, %{"text_x" => String.duplicate("a", 270)})

      assert {:ok, post} = Social.update_texts(post, %{"text_x" => "Shorter"})
      assert post.text_x == "Shorter"
    end

    test "rejected: no job, no second decision", %{post: post} do
      assert {:ok, post} = Social.reject(post, "admin@test")
      assert post.status == "rejected"
      refute_enqueued(worker: SocialPublishWorker)
      assert Social.approve(post, ["x"], %{}, "admin@test") == {:error, :not_draft}
    end
  end

  describe "Buffer adapter" do
    defp stub_buffer(test_pid) do
      Req.Test.stub(Buffer, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => query, "variables" => vars} = Jason.decode!(body)
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer test-key"]

        cond do
          query =~ "organizations" ->
            Req.Test.json(conn, %{
              "data" => %{"account" => %{"organizations" => [%{"id" => "org1"}]}}
            })

          query =~ "channels" ->
            Req.Test.json(conn, %{
              "data" => %{
                "channels" => [
                  %{
                    "id" => "li1",
                    "name" => "syli-atlas",
                    "service" => "linkedin",
                    "isDisconnected" => false
                  },
                  %{
                    "id" => "tw1",
                    "name" => "syliatlas",
                    "service" => "twitter",
                    "isDisconnected" => false
                  }
                ]
              }
            })

          query =~ "createPost" ->
            send(test_pid, {:created, vars["input"]})

            Req.Test.json(conn, %{
              "data" => %{
                "createPost" => %{"__typename" => "PostActionSuccess", "post" => %{"id" => "p42"}}
              }
            })
        end
      end)
    end

    test "adds to the queue of the right channel, never a first comment" do
      stub_buffer(self())

      assert {:ok, "p42"} =
               Buffer.publish(:linkedin, %{
                 text: "Bonjour",
                 image_url: "https://syliatlas.com/og/v/fr.png"
               })

      assert_received {:created, input}
      assert input["channelId"] == "li1"
      assert input["mode"] == "addToQueue"
      assert input["assets"] == [%{"image" => %{"url" => "https://syliatlas.com/og/v/fr.png"}}]
      refute Map.has_key?(input, "metadata")

      assert {:ok, "p42"} = Buffer.publish(:x, %{text: "Hello"})
      assert_received {:created, %{"channelId" => "tw1", "assets" => []} = x}
      refute Map.has_key?(x, "metadata")
    end

    test "Buffer's refusal comes back as an error" do
      Req.Test.stub(Buffer, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        cond do
          body =~ "organizations" ->
            Req.Test.json(conn, %{
              "data" => %{"account" => %{"organizations" => [%{"id" => "o"}]}}
            })

          body =~ "channels" ->
            Req.Test.json(conn, %{"data" => %{"channels" => []}})
        end
      end)

      assert {:error, "aucun compte X connecté dans Buffer"} = Buffer.publish(:x, %{text: "t"})
    end
  end
end
