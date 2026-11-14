defmodule SyliAtlas.BudgetsTest do
  use SyliAtlas.DataCase, async: false
  use Oban.Testing, repo: SyliAtlas.Repo, engine: Oban.Engines.Lite

  alias SyliAtlas.{BudgetFixtures, Budgets}
  alias SyliAtlas.Budgets.{Law, Profile, Proposal}

  setup do
    BudgetFixtures.seed!()
    :ok
  end

  describe "catalog" do
    test "every one of the 54 countries has a profile and a document" do
      assert length(Budgets.list_profiles()) == 54
      assert Budgets.get_profile("MLI").legislature_kind == "transition"
      assert Budgets.get_profile("NER").legislature_kind == "none"
      assert Budgets.get_profile("ERI").legislature_kind == "suspended"

      overview = Budgets.overview()
      assert length(overview["countries"]) == 54
      assert overview["counts"] == %{"official" => 0, "imf" => 54}
      assert overview["imf"]["label"] =~ "Fiscal Monitor"

      mali = Budgets.country("MLI")
      assert mali["level"] == "imf"
      assert mali["currency"] == "XOF"
      assert is_number(mali["imf"]["revenue"]["2026"])
      assert mali["profile"]["legislature"]["fr"] == "Conseil national de Transition"
    end

    test "only links checked by hand go public" do
      assert Budgets.country("GIN")["profile"]["gazette_url"] =~ "journal-officiel.sgg.gov.gn"
      # Kenya's links are in the catalog but not checked yet.
      assert Budgets.get_profile("KEN").gazette_url
      refute Budgets.country("KEN")["profile"]["gazette_url"]
    end

    test "a profile edited in the admin is never overwritten by the bundled file" do
      profile = Budgets.get_profile!("GNB")

      {:ok, _} =
        Budgets.update_profile(profile, %{
          "legislature_fr" => "Conseil national de transition",
          "verified" => "true"
        })

      Budgets.seed!()
      assert Budgets.get_profile("GNB").legislature_fr == "Conseil national de transition"
      assert Budgets.get_profile("GNB").edited_at
    end

    test "watching a page needs its address and a valid pattern" do
      cs = Profile.changeset(Budgets.get_profile!("MLI"), %{"collection_mode" => "auto"})
      assert %{auto_url: [_]} = errors_on(cs)

      cs =
        Profile.changeset(Budgets.get_profile!("MLI"), %{
          "collection_mode" => "auto",
          "auto_url" => "https://sgg-mali.ml/JO/2026/",
          "auto_pattern" => "(["
        })

      assert %{auto_pattern: [_]} = errors_on(cs)
    end
  end

  describe "documents" do
    test "a file is kept raw once per country" do
      file = %{
        body: "%PDF-1.7 loi de finances",
        content_type: "application/pdf",
        filename: "lfr.pdf"
      }

      assert {:ok, doc, :new} = Budgets.store_document("MLI", "upload", file)
      assert doc.status == "new"
      assert Budgets.document_body(doc) == {:ok, "%PDF-1.7 loi de finances"}
      assert {:ok, same, :duplicate} = Budgets.store_document("MLI", "upload", file)
      assert same.id == doc.id
      # Another country may receive the same file.
      assert {:ok, _, :new} = Budgets.store_document("SEN", "upload", file)
      assert {:error, :empty} = Budgets.store_document("MLI", "upload", %{file | body: ""})
    end
  end

  describe "proposals and laws" do
    test "amounts and dates are read as people write them" do
      {:ok, p} =
        Budgets.propose(
          BudgetFixtures.law_attrs(%{
            "revenue" => "3 372 895 000 000",
            "expenditure" => "3.993.319.000.000,00",
            "voted_on" => "09/07/2026",
            "currency" => "xof"
          })
        )

      assert Decimal.equal?(p.revenue, Decimal.new("3372895000000"))
      assert Decimal.equal?(p.expenditure, Decimal.new("3993319000000"))
      assert p.voted_on == ~D[2026-07-09]
      assert p.currency == "XOF"
      assert p.checks == []
    end

    test "checks flag the wrong currency and a figure ten times off the previous law" do
      BudgetFixtures.publish!(%{"kind" => "initial", "expenditure" => "3578217000000"})

      {:ok, p} =
        Budgets.propose(
          BudgetFixtures.law_attrs(%{"currency" => "GNF", "expenditure" => "399331900000"})
        )

      codes = Enum.map(p.checks, & &1["code"])
      assert "currency" in codes
      assert "expenditure_scale" in codes
      assert SyliAtlas.Budgets.Checks.errors?(p.checks)
    end

    test "dates out of order are an error" do
      {:ok, p} =
        Budgets.propose(
          BudgetFixtures.law_attrs(%{"tabled_on" => "2026-08-01", "voted_on" => "2026-07-09"})
        )

      assert Enum.any?(p.checks, &(&1["code"] == "dates" and &1["level"] == "error"))
    end

    test "approving publishes the law and queues the documents and alerts, in one go" do
      {:ok, p} = Budgets.propose(BudgetFixtures.law_attrs())

      assert {:ok, %Law{} = law} =
               Budgets.approve(p, %{"stage" => "published", "published_on" => "2026-07-17"})

      assert law.stage == "published"
      assert law.published_on == ~D[2026-07-17]
      assert Repo.get!(Proposal, p.id).status == "approved"
      assert Repo.get!(Proposal, p.id).law_id == law.id
      assert_enqueued(worker: SyliAtlas.Workers.BudgetPublishWorker, args: %{"law_id" => law.id})
      assert {:error, :already_reviewed} = Budgets.approve(Repo.get!(Proposal, p.id), %{})
    end

    test "approving needs an https link to the official text" do
      {:ok, p} = Budgets.propose(BudgetFixtures.law_attrs(%{"source_url" => nil}))
      assert {:error, %Ecto.Changeset{} = cs} = Budgets.approve(p, %{})
      assert %{source_url: [_]} = errors_on(cs)

      assert {:error, cs} = Budgets.approve(p, %{"source_url" => "http://sgg-mali.ml/jo.pdf"})
      assert %{source_url: [_]} = errors_on(cs)
      assert Repo.get!(Proposal, p.id).status == "pending"
      refute_enqueued(worker: SyliAtlas.Workers.BudgetPublishWorker)
    end

    test "a new stage of the same law updates it instead of adding a row" do
      law = BudgetFixtures.publish!()
      again = BudgetFixtures.publish!(%{"stage" => "published", "published_on" => "2026-07-17"})
      assert again.id == law.id
      assert Repo.aggregate(Law, :count) == 1
    end

    test "rejecting leaves nothing online" do
      {:ok, p} = Budgets.propose(BudgetFixtures.law_attrs())
      assert {:ok, %Proposal{status: "rejected"}} = Budgets.reject(p)
      assert Budgets.list_laws("MLI") == []
    end

    test "documents: a country with a law of this year is « official », latest laws first" do
      BudgetFixtures.publish!(%{"kind" => "initial", "voted_on" => "2025-12-04"})
      BudgetFixtures.publish!()

      BudgetFixtures.publish!(%{
        "country_code" => "GIN",
        "currency" => "GNF",
        "voted_on" => "2026-11-07",
        "revenue" => "60000000000000",
        "expenditure" => "67925870000000"
      })

      overview = Budgets.overview()
      assert overview["counts"]["official"] == 2

      assert [%{"country_code" => "GIN"}, %{"country_code" => "MLI", "kind" => "amending"} | _] =
               overview["latest"]

      mali = Budgets.country("MLI")
      assert mali["level"] == "official"
      assert Enum.map(mali["laws"], & &1["kind"]) == ["amending", "initial"]
      assert hd(mali["laws"])["expenditure"] == "3993319000000"
    end
  end
end
