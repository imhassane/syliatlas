defmodule SyliAtlas.Social.ShareTest do
  use SyliAtlas.DataCase, async: false
  use Oban.Testing, repo: SyliAtlas.Repo, engine: Oban.Engines.Lite

  alias SyliAtlas.Repo
  alias SyliAtlas.Social
  alias SyliAtlas.Social.{Buffer, Clock, Pages, Post, Writer}
  alias SyliAtlas.Workers.{SocialPublishWorker, SocialSyncWorker}

  setup do
    SyliAtlas.Fixtures.load_snapshot!()
    :ok
  end

  defp page_attrs(path \\ "/fr/pays/cote-d-ivoire") do
    {:ok, page} = Pages.describe(path)
    Pages.draft(page)
  end

  defp with_buffer(fun) do
    previous = Application.get_env(:syli_atlas, SyliAtlas.Social)

    Application.put_env(
      :syli_atlas,
      SyliAtlas.Social,
      Keyword.put(previous, :adapter, Buffer)
    )

    try do
      fun.()
    after
      Application.put_env(:syli_atlas, SyliAtlas.Social, previous)
    end
  end

  describe "a page of the site" do
    test "an address of the site or a path, public pages only" do
      assert Pages.normalize("https://syliatlas.com/fr/afrique/produits/cacao?x=1#a") ==
               {:ok, "/fr/afrique/produits/cacao"}

      assert Pages.normalize("/en/debt/") == {:ok, "/en/debt"}
      assert {:error, _} = Pages.normalize("https://example.com/fr/dette")
      assert {:error, _} = Pages.normalize("/admin/reseaux")
      assert {:error, _} = Pages.normalize("dette")
    end

    test "reads the page and its English twin, then drafts X in English, LinkedIn in French" do
      assert {:ok, page} = Pages.describe("/fr/pays/cote-d-ivoire")
      assert page.path_fr == "/fr/pays/cote-d-ivoire"
      assert page.path_en == "/en/countries/cote-d-ivoire"
      assert page.title_fr =~ "PIB, croissance"
      assert page.title_en =~ "Côte d'Ivoire: GDP"
      assert page.description_en =~ "growth"
      assert page.area_code == "CIV"

      attrs = Pages.draft(page)
      assert attrs.kind == "page"
      assert attrs.page_path == "/fr/pays/cote-d-ivoire"
      assert attrs.link_x =~ "/en/countries/cote-d-ivoire?utm_source=x&utm_medium=social"
      assert attrs.link_linkedin =~ "/fr/pays/cote-d-ivoire?utm_source=linkedin"
      assert attrs.image_url_x =~ "/en/countries/cote-d-ivoire.png"
      assert attrs.text_x =~ "#IvoryCoast #Africa #Economy\n\nFigures and sources:"
      assert attrs.text_linkedin =~ "Lien ci-dessous.\n\n#CôteDIvoire"
      assert Post.x_length(attrs.text_x, attrs.link_x) <= Post.x_limit()
    end

    test "an English page finds its French twin; a missing page is an error" do
      assert {:ok, page} = Pages.describe("/en/countries/cote-d-ivoire")
      assert page.path_fr == "/fr/pays/cote-d-ivoire"
      assert {:error, "Cette page n'existe pas sur le site."} = Pages.describe("/fr/nulle-part")
    end

    test "the head of a page: title without the site's name, description, translations" do
      head =
        Pages.head("""
        <html><head><title>Cacao &amp; chocolat · Syli Atlas</title>
        <meta name="description" content="L&#39;Afrique et le cacao">
        <link rel="alternate" hreflang="en" href="https://syliatlas.com/en/africa/products/cocoa">
        <link rel="alternate" hreflang="x-default" href="https://syliatlas.com/en">
        </head><body><nav>Menu</nav><main id="main"><h1>Cacao</h1><script>x()</script><p>Fèves</p></main></body></html>
        """)

      assert head.title == "Cacao & chocolat"
      assert head.description == "L'Afrique et le cacao"
      assert head.alternates == %{"en" => "https://syliatlas.com/en/africa/products/cocoa"}
      assert head.text == "Cacao Fèves"
    end

    test "Claude's proposal replaces the texts, hashtags added after" do
      Req.Test.stub(Writer, fn conn ->
        Req.Test.json(conn, %{
          "content" => [
            %{
              "type" => "tool_use",
              "input" => %{
                "x" => "Côte d'Ivoire in figures:",
                "linkedin" => "La Côte d'Ivoire en chiffres."
              }
            }
          ]
        })
      end)

      Application.put_env(:syli_atlas, Writer,
        api_key: "k",
        req_options: [plug: {Req.Test, Writer}, retry: false]
      )

      on_exit(fn ->
        Application.put_env(:syli_atlas, Writer,
          req_options: [plug: {Req.Test, Writer}, retry: false]
        )
      end)

      {:ok, page} = Pages.describe("/fr/pays/cote-d-ivoire")
      assert {:ok, texts} = Writer.propose(page)
      attrs = Pages.draft(page, texts)
      assert attrs.text_x =~ "Côte d'Ivoire in figures: #IvoryCoast"
      assert attrs.text_linkedin =~ "La Côte d'Ivoire en chiffres."
    end
  end

  describe "share, queue, schedule" do
    test "« Ajouter à la file »: kept here without a date, for the networks chosen" do
      attrs = page_attrs()
      assert {:ok, post} = Social.share_page(attrs, %{}, ["linkedin"], "queue", "admin@test")
      assert post.status == "ready"
      assert post.linkedin_state == "waiting" and post.x_state == nil
      assert Post.chosen(post) == ["linkedin"]
      refute_enqueued(worker: SocialPublishWorker)
      assert [%Post{id: id}] = Social.board().ready
      assert id == post.id
      assert Social.quota().linkedin == 0

      # Scheduled later: the networks chosen go, through the job.
      assert {:ok, post} = Social.approve(post, Post.chosen(post), %{}, "admin@test")
      assert post.linkedin_state == "pending" and post.x_state == nil
      assert_enqueued(worker: SocialPublishWorker, args: %{"post_id" => post.id})
    end

    test "« Envoyer à valider » makes a draft; « Publier maintenant » asks for it at once" do
      assert {:ok, draft} = Social.share_page(page_attrs(), %{}, ["x", "linkedin"], "draft", "a")
      assert draft.status == "draft"
      assert Social.count_drafts() == 1

      assert {:ok, now} = Social.share_page(page_attrs(), %{}, ["x"], "now", "a")
      assert_enqueued(worker: SocialPublishWorker, args: %{"post_id" => now.id, "mode" => "now"})
      :ok = perform_job(SocialPublishWorker, %{"post_id" => now.id, "mode" => "now"})
      now = Social.get!(now.id)
      assert now.x_state == "simulated" and now.x_sent_at

      assert {:error, :no_network} = Social.share_page(page_attrs(), %{}, [], "draft", "a")
    end

    test "edited texts are kept; too long for X is refused" do
      assert {:ok, post} =
               Social.share_page(page_attrs(), %{text_x: "Short"}, ["x"], "draft", "a")

      assert post.text_x == "Short"

      assert {:error, %Ecto.Changeset{}} =
               Social.share_page(
                 page_attrs(),
                 %{text_x: String.duplicate("a", 300)},
                 ["x"],
                 "draft",
                 "a"
               )
    end

    test "« Retirer » takes a scheduled post out of Buffer, back in the queue" do
      {:ok, post} = Social.share_page(page_attrs(), %{}, ["x", "linkedin"], "schedule", "a")
      :ok = perform_job(SocialPublishWorker, %{"post_id" => post.id})

      post =
        post.id
        |> Social.get!()
        |> Ecto.Changeset.change(x_state: "queued", linkedin_state: "queued")
        |> Repo.update!()

      assert {:ok, post} = Social.withdraw(post, "a")
      assert post.status == "ready"
      assert Post.chosen(post) == ["x", "linkedin"]
      assert post.x_ref == nil

      assert {:error, :not_scheduled} = Social.withdraw(post, "a")
    end

    test "quota: a network with 10 posts in Buffer's queue is full" do
      for i <- 1..10 do
        %Post{}
        |> Post.draft_changeset(%{key: "k#{i}", kind: "page", text_x: "x", text_linkedin: "l"})
        |> Ecto.Changeset.change(status: "done", x_state: "queued")
        |> Repo.insert!()
      end

      assert Social.quota().x == 10
      assert Social.full_networks() == ["x"]
    end

    test "the page's latest post, from any of its languages" do
      {:ok, _} = Social.share_page(page_attrs(), %{}, ["x"], "queue", "a")
      assert %Post{status: "ready"} = Social.latest_for_page("/fr/pays/cote-d-ivoire")
      assert %Post{} = Social.latest_for_page("/en/countries/cote-d-ivoire")
      assert Social.latest_for_page("/fr/dette") == nil
    end
  end

  describe "slots" do
    test "Paris time, summer and winter" do
      assert Clock.paris(~U[2026-11-18 09:00:00Z]) == ~N[2026-11-18 10:00:00]
      assert Clock.paris(~U[2026-07-01 08:00:00Z]) == ~N[2026-07-01 10:00:00]
      assert Clock.utc(~N[2026-11-18 14:00:00]) == ~U[2026-11-18 13:00:00Z]
      assert Clock.utc(~N[2026-03-30 10:00:00]) == ~U[2026-03-30 08:00:00Z]
      assert Clock.label(~U[2026-11-18 13:00:00Z]) == "mer. 18 nov. à 14:00"
    end

    test "the next free slot skips the past, the weekend and the slots taken" do
      tue_evening = ~U[2026-11-17 18:40:00Z]
      assert Social.next_slots(tue_evening)["x"] == ~U[2026-11-18 09:00:00Z]

      %Post{}
      |> Post.draft_changeset(%{key: "g", kind: "page", text_x: "x", text_linkedin: "l"})
      |> Ecto.Changeset.change(
        status: "done",
        x_state: "queued",
        x_due_at: ~U[2026-11-18 09:00:00Z]
      )
      |> Repo.insert!()

      assert Social.next_slots(tue_evening) == %{
               "x" => ~U[2026-11-18 13:00:00Z],
               "linkedin" => ~U[2026-11-18 09:00:00Z]
             }

      assert Social.next_slot_label(["x"], tue_evening) == "mer. 18 nov. à 14:00"
      assert Social.next_slot_label(["x", "linkedin"], tue_evening) =~ "X mer. 18 nov. à 14:00"

      friday_night = ~U[2026-11-20 20:00:00Z]
      assert Social.next_slots(friday_night)["linkedin"] == ~U[2026-11-23 09:00:00Z]
    end

    test "the week: past, sent, scheduled and free slots" do
      %Post{}
      |> Post.draft_changeset(%{key: "z", kind: "page", text_x: "x", text_linkedin: "l"})
      |> Ecto.Changeset.change(
        status: "done",
        x_state: "sent",
        x_sent_at: ~U[2026-11-17 09:00:48Z],
        linkedin_state: "queued",
        linkedin_due_at: ~U[2026-11-18 13:00:00Z]
      )
      |> Repo.insert!()

      week = Social.week(~U[2026-11-17 18:40:00Z])
      assert hd(week.days) == ~D[2026-11-16]
      assert week.times == ~w(10:00 14:00 19:00)
      assert week.cells[{~D[2026-11-16], "10:00"}].kind == :past
      assert week.cells[{~D[2026-11-17], "10:00"}].kind == :sent
      assert week.cells[{~D[2026-11-18], "14:00"}].kind == :scheduled
      assert week.cells[{~D[2026-11-19], "10:00"}].kind == :free

      # From Saturday, next week.
      assert hd(Social.week(~U[2026-11-21 10:00:00Z]).days) == ~D[2026-11-23]
    end
  end

  describe "Buffer's side" do
    defp stub(test_pid, posts) do
      Req.Test.stub(Buffer, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => query, "variables" => vars} = Jason.decode!(body)

        cond do
          query =~ "organizations" ->
            Req.Test.json(conn, %{
              "data" => %{"account" => %{"organizations" => [%{"id" => "org1"}]}}
            })

          query =~ "postingSchedule" ->
            Req.Test.json(conn, %{
              "data" => %{
                "channels" => [
                  %{
                    "service" => "twitter",
                    "isDisconnected" => false,
                    "timezone" => "Europe/Paris",
                    "postingSchedule" => [
                      %{"day" => "mon", "paused" => false, "times" => ["14:00", "10:00"]},
                      %{"day" => "sat", "paused" => true, "times" => ["10:00"]}
                    ]
                  }
                ]
              }
            })

          query =~ "channels" ->
            Req.Test.json(conn, %{
              "data" => %{
                "channels" => [
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
              "data" => %{"createPost" => %{"post" => %{"id" => "p9"}}}
            })

          query =~ "deletePost" ->
            send(test_pid, {:deleted, vars["input"]["id"]})

            Req.Test.json(conn, %{
              "data" => %{"deletePost" => %{"__typename" => "DeletePostSuccess"}}
            })

          query =~ "posts(" ->
            send(test_pid, {:posts_query, query})
            Req.Test.json(conn, %{"data" => %{"posts" => %{"edges" => posts}}})
        end
      end)
    end

    test "publishes now with shareNow, reads the schedule, deletes" do
      stub(self(), [])
      assert {:ok, "p9"} = Buffer.publish(:x, %{text: "Now"}, :now)
      assert_received {:created, %{"mode" => "shareNow"}}

      assert {:ok, %{days: %{"mon" => ["10:00", "14:00"], "sat" => []}}} = Buffer.schedule(:x)
      assert Buffer.delete("p9") == :ok
      assert_received {:deleted, "p9"}
    end

    test "sync: sent with its figures, failed with Buffer's error, due time, deleted in Buffer" do
      node = fn id, status, extra ->
        %{"node" => Map.merge(%{"id" => id, "status" => status}, extra)}
      end

      stub(self(), [
        node.("b1", "sent", %{
          "dueAt" => "2026-11-17T09:00:00.000Z",
          "sentAt" => "2026-11-17T09:00:48.986Z",
          "metrics" => [%{"type" => "impressions", "value" => 120.0}]
        }),
        node.("b2", "error", %{"error" => %{"message" => "Token expired"}}),
        node.("b3", "scheduled", %{"dueAt" => "2026-11-18T09:00:00.000Z"}),
        node.("other", "sent", %{})
      ])

      insert = fn key, changes ->
        %Post{}
        |> Post.draft_changeset(%{key: key, kind: "page", text_x: "x", text_linkedin: "l"})
        |> Ecto.Changeset.change(Map.merge(%{status: "done"}, changes))
        |> Repo.insert!()
      end

      a =
        insert.("a", %{
          x_state: "queued",
          x_ref: "b1",
          linkedin_state: "queued",
          linkedin_ref: "b2"
        })

      b = insert.("b", %{x_state: "queued", x_ref: "b3"})
      c = insert.("c", %{x_state: "queued", x_ref: "gone"})

      with_buffer(fn ->
        assert Social.sync_needed?()
        assert {:ok, 3} = Social.sync()
      end)

      assert_received {:posts_query, q}
      assert q =~ "metrics"

      a = Social.get!(a.id)
      assert a.x_state == "sent" and a.x_sent_at == ~U[2026-11-17 09:00:48Z]
      assert a.x_metrics == %{"impressions" => 120.0}
      assert a.linkedin_state == "failed" and a.linkedin_error == "Token expired"
      assert Social.get!(b.id).x_due_at == ~U[2026-11-18 09:00:00Z]
      assert Social.get!(c.id).x_error =~ "Introuvable dans Buffer"
      assert {_, :ok} = Social.last_sync()

      # The board: sent in Publiés with its figures, failures apart.
      board = Social.board()
      assert Enum.any?(board.published, &(&1.id == a.id))
      assert Enum.any?(board.scheduled, &(&1.id == b.id))
      assert Enum.any?(board.failed, &(&1.id == c.id))
    end

    test "the sync job asks nothing when simulated" do
      assert :ok = perform_job(SocialSyncWorker, %{})
      refute Social.sync_needed?()
    end
  end
end
