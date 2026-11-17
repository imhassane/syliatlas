defmodule SyliAtlasWeb.AdminSocialTest do
  use SyliAtlasWeb.ConnCase, async: false
  use Oban.Testing, repo: SyliAtlas.Repo, engine: Oban.Engines.Lite

  alias SyliAtlas.{AccountsFixtures, Social}
  alias SyliAtlas.Social.Post
  alias SyliAtlas.Workers.SocialPublishWorker

  defp admin, do: AccountsFixtures.admin_conn()

  setup do
    SyliAtlas.Geo.seed_areas!()

    {:ok, post} =
      Social.create_draft(%{
        key: "rating:ZMB:moodys:2026-10-30",
        kind: "rating",
        area_code: "ZMB",
        text_x: "Moody's upgrades Zambia to Caa1 (from Caa2), outlook positive.",
        text_linkedin: "Moody's relève la note de la Zambie : Caa2 → Caa1.",
        link_x: "https://syliatlas.com/en/credit-ratings/zambia?utm_source=x&utm_medium=social",
        link_linkedin:
          "https://syliatlas.com/fr/notations/zambie?utm_source=linkedin&utm_medium=social"
      })

    {:ok, post: post}
  end

  test "lists the drafts, says Buffer is simulated, counts them in the menu", %{post: post} do
    html = admin() |> get("/admin/reseaux") |> html_response(200)
    assert html =~ ~s(id="post-#{post.id}")
    assert html =~ "Zambie · Notation"
    assert html =~ "Buffer simulé"
    assert html =~ "Moody&#39;s upgrades Zambia"
    assert html =~ ~s(href="/admin/reseaux" aria-current="page")
    assert html =~ ~r/id="admin-nav-social".*?admin-cnt">1</s
  end

  test "approve sends to the job, then the history shows it simulated", %{post: post} do
    conn =
      admin()
      |> post("/admin/reseaux/#{post.id}/valider", %{
        "post" => %{"text_x" => "Edited for X", "text_linkedin" => "Modifié"}
      })

    assert redirected_to(conn) == "/admin/reseaux"
    assert_enqueued(worker: SocialPublishWorker, args: %{"post_id" => post.id})
    :ok = perform_job(SocialPublishWorker, %{"post_id" => post.id})

    post = Social.get!(post.id)
    assert post.text_x == "Edited for X"
    assert post.x_state == "simulated" and post.linkedin_state == "simulated"

    html = admin() |> get("/admin/reseaux") |> html_response(200)
    assert html =~ ~s(id="history-#{post.id}")
    assert html =~ "Simulé"
    assert html =~ ~s(id="social-empty")
  end

  test "only LinkedIn, save without approving, reject", %{post: post} do
    admin()
    |> post("/admin/reseaux/#{post.id}", %{
      "post" => %{"text_x" => "New", "text_linkedin" => "Nouveau"}
    })

    assert Social.get!(post.id).text_x == "New"
    assert Social.get!(post.id).status == "draft"

    admin() |> post("/admin/reseaux/#{post.id}/valider", %{"reseaux" => "linkedin"})
    post = Social.get!(post.id)
    assert post.linkedin_state == "pending" and post.x_state == nil

    conn = admin() |> post("/admin/reseaux/#{post.id}/rejeter")
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "plus un brouillon"
  end

  test "a recent decision without post can be prepared from the page" do
    r =
      %SyliAtlas.Ratings.Rating{}
      |> SyliAtlas.Ratings.Rating.changeset(%{
        country_code: "SEN",
        agency: "moodys",
        rating: "Ca",
        outlook: "stable",
        action_type: "downgrade",
        action_date: Date.utc_today() |> Date.add(-5) |> Date.to_iso8601()
      })
      |> SyliAtlas.Repo.insert!()

    html = admin() |> get("/admin/reseaux") |> html_response(200)
    assert html =~ ~s(id="candidate-#{r.id}")

    conn = admin() |> post("/admin/reseaux/preparer/notation/#{r.id}")
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Brouillon préparé."
    assert Enum.any?(Social.drafts(), &(&1.key =~ "rating:SEN:moodys"))

    html = admin() |> get("/admin/reseaux") |> html_response(200)
    refute html =~ ~s(id="candidate-#{r.id}")
  end

  test "a failed network shows an alert opening the error, and can be sent again", %{post: post} do
    {:ok, post} = Social.approve(post, ["x", "linkedin"], %{}, "admin@test")

    post
    |> Ecto.Changeset.change(
      x_state: "queued",
      linkedin_state: "failed",
      linkedin_error: "Invalid post"
    )
    |> SyliAtlas.Repo.update!()

    html = admin() |> get("/admin/reseaux") |> html_response(200)
    assert html =~ ~s(popovertarget="error-#{post.id}-linkedin")
    assert html =~ ~r/<div[^>]*popover[^>]*id="error-#{post.id}-linkedin"/
    assert html =~ "Invalid post"
    assert html =~ ~s(id="resend-#{post.id}-x")

    conn = admin() |> post("/admin/reseaux/#{post.id}/renvoyer/linkedin")
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Nouvel envoi lancé."
    assert Social.get!(post.id).linkedin_state == "pending"
  end

  test "the board: Buffer's band, the week, the four columns", %{post: post} do
    html = admin() |> get("/admin/reseaux") |> html_response(200)

    for id <-
          ~w(social-service social-quota social-week social-board social-drafts social-ready social-scheduled social-published share-form) do
      assert html =~ ~s(id="#{id}"), "missing #{id}"
    end

    assert html =~ ~s(id="edit-#{post.id}")
    assert html =~ ~s(id="queue-#{post.id}")
    assert html =~ "0 / 10"
  end

  test "a draft goes in the queue without a date, then is scheduled from there", %{post: post} do
    conn = admin() |> post("/admin/reseaux/#{post.id}/file")
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Ajouté à la file"
    assert Social.get!(post.id).status == "ready"
    refute_enqueued(worker: SocialPublishWorker)

    html = admin() |> get("/admin/reseaux") |> html_response(200)
    assert html =~ ~s(id="ready-#{post.id}")

    admin() |> post("/admin/reseaux/#{post.id}/valider")
    assert_enqueued(worker: SocialPublishWorker, args: %{"post_id" => post.id})
    :ok = perform_job(SocialPublishWorker, %{"post_id" => post.id})
    assert Social.get!(post.id).x_state == "simulated"
  end

  test "the composer of a draft: edit, then publish now", %{post: post} do
    html = admin() |> get("/admin/reseaux/#{post.id}/modifier") |> html_response(200)
    assert html =~ ~s(id="social-composer")
    assert html =~ ~s(id="preview-x")
    assert html =~ ~s(id="action-queue")

    conn =
      admin()
      |> post("/admin/reseaux/#{post.id}", %{
        "action" => "now",
        "reseaux" => ["x"],
        "post" => %{"text_x" => "Now on X", "text_linkedin" => "Maintenant"}
      })

    assert redirected_to(conn) == "/admin/reseaux"
    assert_enqueued(worker: SocialPublishWorker, args: %{"post_id" => post.id, "mode" => "now"})
    post = Social.get!(post.id)
    assert post.text_x == "Now on X" and post.x_state == "pending" and post.linkedin_state == nil
  end

  describe "sharing a page" do
    setup do
      SyliAtlas.Fixtures.load_snapshot!()
      :ok
    end

    test "the page's post, ready to edit; then « Ajouter à la file »" do
      html =
        admin()
        |> get("/admin/reseaux/partager?page=https://syliatlas.com/fr/pays/cote-d-ivoire")
        |> html_response(200)

      assert html =~ ~s(id="social-composer")
      assert html =~ ~s(name="page" value="/fr/pays/cote-d-ivoire")
      assert html =~ "/en/countries/cote-d-ivoire"
      assert html =~ "Figures and sources:"

      conn =
        admin()
        |> post("/admin/reseaux/partager", %{
          "page" => "/fr/pays/cote-d-ivoire",
          "action" => "queue",
          "reseaux" => ["x", "linkedin"],
          "post" => %{"text_x" => "Côte d'Ivoire, in figures:", "text_linkedin" => "En chiffres."}
        })

      assert redirected_to(conn) == "/admin/reseaux"

      assert %Post{status: "ready", kind: "page"} =
               post = Social.latest_for_page("/fr/pays/cote-d-ivoire")

      assert post.text_x == "Côte d'Ivoire, in figures:"

      json =
        admin()
        |> get("/admin/reseaux/page?chemin=/en/countries/cote-d-ivoire")
        |> json_response(200)

      assert json["state"] == "en file"
      assert json["share"] =~ "/admin/reseaux/partager?page="
    end

    test "« Programmer » from the composer goes to the job; no network is refused" do
      conn =
        admin()
        |> post("/admin/reseaux/partager", %{
          "page" => "/fr/pays/cote-d-ivoire",
          "action" => "schedule",
          "reseaux" => ["linkedin"]
        })

      assert redirected_to(conn) == "/admin/reseaux"
      post = Social.latest_for_page("/fr/pays/cote-d-ivoire")
      assert post.linkedin_state == "pending" and post.x_state == nil
      assert_enqueued(worker: SocialPublishWorker, args: %{"post_id" => post.id})

      html =
        admin()
        |> post("/admin/reseaux/partager", %{
          "page" => "/fr/pays/cote-d-ivoire",
          "action" => "draft"
        })
        |> html_response(200)

      assert html =~ "Choisissez au moins un réseau."
    end

    test "an address outside the site, or a missing page, comes back with its error" do
      html =
        admin() |> get("/admin/reseaux/partager?page=https://example.com/x") |> html_response(200)

      assert html =~ ~s(id="picker-form")
      assert html =~ "pas une page de Syli Atlas"

      html = admin() |> get("/admin/reseaux/partager?page=/fr/nulle-part") |> html_response(200)
      assert html =~ "existe pas sur le site"
    end

    test "never shared: the admin bar says so" do
      json = admin() |> get("/admin/reseaux/page?chemin=/fr/dette") |> json_response(200)
      assert json["state"] == "jamais partagée"
    end
  end

  test "visitors are sent to the sign-in page", %{conn: conn} do
    assert conn |> get("/admin/reseaux") |> redirected_to() == "/fr/connexion"
  end
end
