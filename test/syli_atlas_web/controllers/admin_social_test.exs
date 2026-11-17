defmodule SyliAtlasWeb.AdminSocialTest do
  use SyliAtlasWeb.ConnCase, async: false
  use Oban.Testing, repo: SyliAtlas.Repo, engine: Oban.Engines.Lite

  alias SyliAtlas.{AccountsFixtures, Social}
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

  test "visitors are sent to the sign-in page", %{conn: conn} do
    assert conn |> get("/admin/reseaux") |> redirected_to() == "/fr/connexion"
  end
end
