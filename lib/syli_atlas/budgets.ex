defmodule SyliAtlas.Budgets do
  @moduledoc """
  State budgets of the 54 countries and the laws that vote them.

  Every country has a budget page from the start: who votes the budget,
  where its laws are published, and the IMF's revenue and expenditure in %
  of GDP (`SyliAtlas.Budgets.Imf`). Budget laws come on top, country by
  country, as they are collected:

    1. a document arrives: dropped in the admin, or fetched from a watched
       page (`BudgetFetchWorker`); it stays raw in object storage;
    2. the AI reads it (`BudgetExtractWorker`, `SyliAtlas.Budgets.Extractor`)
       and proposes the law's figures, with the page of each one; the
       automatic checks run (`SyliAtlas.Budgets.Checks`);
    3. a human approves it in the admin, with the link to the official
       text: it becomes a `Law`, the documents are rebuilt and the alerts
       run (`BudgetPublishWorker`), in the same transaction as the approval.

  Pages only read the documents: `budget:overview` and one
  `budget:country:<code>` per country (table `snapshots`).
  """
  import Ecto.Query
  require Logger

  alias SyliAtlas.Repo
  alias SyliAtlas.Budgets.{Checks, Document, Imf, Law, Profile, Proposal}
  alias SyliAtlas.Economy.Currencies

  @format 1
  @kind_order %{"settlement" => 0, "amending" => 1, "initial" => 2, "provisional" => 3}

  def format, do: @format

  # Catalog ----------------------------------------------------------------

  def catalog_path, do: Application.app_dir(:syli_atlas, "priv/data/budget_catalog.json")

  @doc """
  Upserts the bundled catalog (who votes, where laws are published), except
  rows edited in the admin, then rebuilds the documents. Returns the count.
  """
  def seed! do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    rows = catalog_path() |> File.read!() |> Jason.decode!() |> Map.fetch!("countries")

    edited =
      MapSet.new(
        Repo.all(from p in Profile, where: not is_nil(p.edited_at), select: p.country_code)
      )

    entries =
      for {code, row} <- rows, not MapSet.member?(edited, code) do
        %{
          country_code: code,
          legislature_fr: row["legislature_fr"],
          legislature_en: row["legislature_en"],
          legislature_kind: row["legislature_kind"],
          gazette_name: row["gazette_name"],
          gazette_url: row["gazette_url"],
          finance_url: row["finance_url"],
          verified: row["verified"] == true,
          notes: row["notes"],
          collection_mode: "manual",
          inserted_at: now,
          updated_at: now
        }
      end

    Repo.insert_all(Profile, entries,
      on_conflict:
        {:replace,
         [
           :legislature_fr,
           :legislature_en,
           :legislature_kind,
           :gazette_name,
           :gazette_url,
           :finance_url,
           :verified,
           :notes,
           :updated_at
         ]},
      conflict_target: [:country_code]
    )

    rebuild!()
    map_size(rows)
  end

  def list_profiles, do: Repo.all(from p in Profile, order_by: p.country_code)
  def get_profile(code), do: Repo.get(Profile, code)
  def get_profile!(code), do: Repo.get!(Profile, code)

  @doc "An edit in the admin; the documents of the country are rebuilt."
  def update_profile(%Profile{} = profile, attrs) do
    with {:ok, profile} <- profile |> Profile.edit_changeset(attrs) |> Repo.update() do
      rebuild!()
      {:ok, profile}
    end
  end

  def change_profile(%Profile{} = profile, attrs \\ %{}), do: Profile.changeset(profile, attrs)

  def auto_profiles,
    do: Repo.all(from p in Profile, where: p.collection_mode == "auto" and not is_nil(p.auto_url))

  # Documents --------------------------------------------------------------

  @max_bytes 32 * 1024 * 1024

  @doc """
  Keeps a file raw and records it for a country. A file already read for the
  country is not recorded again: `{:ok, document, :duplicate}`.
  `file` is `%{body, content_type, url, filename}`.
  """
  def store_document(country_code, origin, %{body: body} = file)
      when origin in ["auto", "upload"] and is_binary(body) do
    cond do
      byte_size(body) == 0 ->
        {:error, :empty}

      byte_size(body) > @max_bytes ->
        {:error, :too_large}

      true ->
        sha = :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)

        case Repo.get_by(Document, country_code: country_code, sha256: sha) do
          %Document{} = existing ->
            {:ok, existing, :duplicate}

          nil ->
            payload =
              SyliAtlas.Market.Ingestion.store!("budget_" <> origin, "budget", nil, %{
                url: file[:url] || "upload:" <> (file[:filename] || "file"),
                status: 200,
                body: body
              })

            document =
              Repo.insert!(%Document{
                country_code: country_code,
                origin: origin,
                url: file[:url],
                filename: file[:filename],
                content_type: file[:content_type],
                sha256: sha,
                raw_payload_id: payload.id,
                status: "new"
              })

            {:ok, document, :new}
        end
    end
  end

  def get_document!(id), do: Repo.get!(Document, id)

  def document_body(%Document{raw_payload_id: id}),
    do: id |> SyliAtlas.Market.Ingestion.get_payload!() |> SyliAtlas.Market.Ingestion.body()

  def set_document_status!(%Document{} = d, status, error \\ nil) do
    d
    |> Ecto.Changeset.change(status: status, error: error && String.slice(error, 0, 250))
    |> Repo.update!()
  end

  def recent_documents(limit \\ 20),
    do: Repo.all(from d in Document, order_by: [desc: d.id], limit: ^limit)

  # Proposals --------------------------------------------------------------

  @doc "A law typed in the admin, checked like an extraction."
  def propose(attrs) do
    %Proposal{}
    |> Proposal.changeset(Map.put(stringify(attrs), "origin", "manual"))
    |> with_checks()
    |> Repo.insert()
  end

  @doc "A law read by the AI from a document."
  def propose_from_document(%Document{} = d, fields, evidence, model) do
    attrs =
      fields
      |> stringify()
      |> Map.merge(%{
        "country_code" => d.country_code,
        "document_id" => d.id,
        "origin" => "extraction",
        "evidence" => evidence,
        "model" => model,
        "source_url" => fields["source_url"] || d.url
      })

    %Proposal{} |> Proposal.changeset(attrs) |> with_checks() |> Repo.insert()
  end

  defp with_checks(%Ecto.Changeset{valid?: false} = cs), do: cs

  defp with_checks(cs) do
    p = Ecto.Changeset.apply_changes(cs)
    Ecto.Changeset.put_change(cs, :checks, checks_for(p))
  end

  @doc "The automatic checks of a proposal, against the country's latest law and GDP."
  def checks_for(%Proposal{} = p) do
    Checks.run(p,
      previous: previous_law(p),
      gdp_local: gdp_local(p.country_code, p.fiscal_year, p.currency)
    )
  end

  defp previous_law(%Proposal{country_code: c} = p) do
    query =
      from l in Law,
        where: l.country_code == ^c and l.kind in ["initial", "amending"],
        order_by: [desc: l.fiscal_year, desc: l.approved_at],
        limit: 1

    # Not the law this proposal would replace.
    query =
      if p.fiscal_year && p.kind,
        do:
          where(
            query,
            [l],
            not (l.fiscal_year == ^p.fiscal_year and l.kind == ^p.kind and
                   l.sequence == ^(p.sequence || 1))
          ),
        else: query

    Repo.one(query)
  end

  # GDP of the year in local currency: IMF GDP in dollars at today's rate.
  defp gdp_local(_code, nil, _currency), do: nil
  defp gdp_local(_code, _year, nil), do: nil

  defp gdp_local(code, year, currency) do
    with json when is_binary(json) <- SyliAtlas.Profiles.Queries.area_profile(code, year, year),
         %{"profile" => %{"series" => series}} <- Jason.decode!(json),
         gdp when is_number(gdp) <- Enum.at(series["gdp_usd_bn"] || [], year - 2015),
         rate when is_number(rate) <- SyliAtlas.Fx.per(SyliAtlas.Fx.latest(), currency) do
      gdp * 1.0e9 * rate
    else
      _ -> nil
    end
  end

  def list_proposals(status, limit \\ 200) do
    Repo.all(
      from p in Proposal,
        where: p.status == ^status,
        order_by: [desc: p.inserted_at, desc: p.id],
        limit: ^limit,
        preload: :document
    )
  end

  def get_proposal!(id), do: Proposal |> Repo.get!(id) |> Repo.preload(:document)

  @doc """
  Publishes a proposal as a law, with the reviewer's corrections (`attrs`):
  in one transaction, the law, the proposal marked approved, and the job that
  rebuilds the documents and runs the alerts.
  """
  def approve(%Proposal{status: "pending"} = proposal, attrs) do
    Repo.transaction(fn ->
      cs = Proposal.approval_changeset(proposal, attrs)

      with {:ok, p} <- Repo.update(cs),
           {:ok, law} <- upsert_law(p),
           {:ok, _} <-
             p
             |> Proposal.review_changeset("approved")
             |> Ecto.Changeset.change(law_id: law.id)
             |> Repo.update() do
        %{"type" => "law", "law_id" => law.id}
        |> SyliAtlas.Workers.BudgetPublishWorker.new()
        |> Oban.insert!()

        law
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def approve(_proposal, _attrs), do: {:error, :already_reviewed}

  def reject(%Proposal{status: "pending"} = p),
    do: p |> Proposal.review_changeset("rejected") |> Repo.update()

  def reject(_), do: {:error, :already_reviewed}

  defp upsert_law(%Proposal{} = p) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs =
      p
      |> Map.take(Proposal.law_fields())
      |> Map.merge(%{country_code: p.country_code, document_id: p.document_id, approved_at: now})

    existing =
      Repo.get_by(Law,
        country_code: p.country_code,
        fiscal_year: p.fiscal_year,
        kind: p.kind,
        sequence: p.sequence || 1
      )

    (existing || %Law{})
    |> Ecto.Changeset.change(attrs)
    |> Repo.insert_or_update()
  end

  # Laws -------------------------------------------------------------------

  def get_law(id), do: Repo.get(Law, id)

  @doc "A country's laws, latest year first."
  def list_laws(country_code) do
    Repo.all(from l in Law, where: l.country_code == ^country_code)
    |> Enum.sort_by(&{-&1.fiscal_year, @kind_order[&1.kind] || 9, -&1.sequence})
  end

  @doc "The laws that moved most recently, every country."
  def latest_laws(limit \\ 12) do
    Repo.all(from(l in Law))
    |> Enum.sort_by(&{Law.last_date(&1) || ~D[1900-01-01], &1.approved_at}, :desc)
    |> Enum.take(limit)
  end

  # Documents of the pages -------------------------------------------------

  @doc "Rebuilds every budget document. Returns the number written."
  def rebuild! do
    now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    countries = for a <- SyliAtlas.Geo.list_areas(), a.kind == "country", do: a.code
    profiles = Map.new(list_profiles(), &{&1.country_code, &1})
    laws = Repo.all(from(l in Law)) |> Enum.group_by(& &1.country_code)
    docs = Enum.map(countries, &country_doc(&1, profiles[&1], Map.get(laws, &1, []), now))

    Repo.transaction(fn ->
      for d <- docs, do: put!("budget:country:" <> d["code"], d, now)
      put!("budget:overview", overview_doc(docs, now), now)
    end)

    length(docs) + 1
  end

  @doc "The document of the hub page (built on the fly if missing)."
  def overview do
    case read("budget:overview") do
      %{"format" => @format} = doc -> doc
      _ -> build_overview()
    end
  end

  @doc "The document of a country's budget page (built on the fly if missing)."
  def country(code) do
    case read("budget:country:" <> code) do
      %{"format" => @format} = doc -> doc
      _ -> country_doc(code, get_profile(code), list_laws(code), nil)
    end
  end

  defp build_overview do
    countries = for a <- SyliAtlas.Geo.list_areas(), a.kind == "country", do: a.code
    profiles = Map.new(list_profiles(), &{&1.country_code, &1})
    laws = Repo.all(from(l in Law)) |> Enum.group_by(& &1.country_code)
    docs = Enum.map(countries, &country_doc(&1, profiles[&1], Map.get(laws, &1, []), nil))
    overview_doc(docs, nil)
  end

  @doc "The year the IMF figures are shown for: the current year."
  def imf_year(today \\ Date.utc_today()), do: today.year

  @doc """
  How a country's budget is known: `"official"` (a budget law collected for
  this year or the previous one) or `"imf"` (the IMF model only).
  """
  def level(laws, today \\ Date.utc_today()) do
    if Enum.any?(
         laws,
         &(&1.fiscal_year >= today.year - 1 and &1.kind in ["initial", "amending"])
       ),
       do: "official",
       else: "imf"
  end

  defp country_doc(code, profile, laws, now) do
    laws = Enum.sort_by(laws, &{-&1.fiscal_year, @kind_order[&1.kind] || 9, -&1.sequence})
    imf = Imf.document()
    entry = Imf.for_country(code) || %{}

    %{
      "format" => @format,
      "built_at" => now,
      "code" => code,
      "currency" => (Currencies.for_country(code) || %{})[:code],
      "level" => level(laws),
      "profile" => profile_doc(profile),
      "imf" => %{
        "label" => imf["source"]["label"],
        "url" => imf["source"]["url"],
        "revenue" => entry["revenue"] || %{},
        "expenditure" => entry["expenditure"] || %{}
      },
      "laws" => Enum.map(laws, &law_doc/1)
    }
  end

  defp profile_doc(nil), do: nil

  defp profile_doc(%Profile{} = p) do
    %{
      "legislature" => %{"fr" => p.legislature_fr, "en" => p.legislature_en},
      "kind" => p.legislature_kind,
      "gazette_name" => p.gazette_name,
      # Only links checked by hand go public.
      "gazette_url" => if(p.verified, do: p.gazette_url),
      "finance_url" => if(p.verified, do: p.finance_url)
    }
  end

  @doc false
  def law_doc(%Law{} = l) do
    %{
      "id" => l.id,
      "fiscal_year" => l.fiscal_year,
      "kind" => l.kind,
      "sequence" => l.sequence,
      "stage" => l.stage,
      "reference" => l.reference,
      "title" => l.title,
      "legislature" => l.legislature,
      "tabled_on" => l.tabled_on && Date.to_iso8601(l.tabled_on),
      "voted_on" => l.voted_on && Date.to_iso8601(l.voted_on),
      "promulgated_on" => l.promulgated_on && Date.to_iso8601(l.promulgated_on),
      "published_on" => l.published_on && Date.to_iso8601(l.published_on),
      "last_date" => (d = Law.last_date(l)) && Date.to_iso8601(d),
      "votes_for" => l.votes_for,
      "votes_against" => l.votes_against,
      "revenue" => l.revenue && Decimal.to_string(l.revenue, :normal),
      "expenditure" => l.expenditure && Decimal.to_string(l.expenditure, :normal),
      "currency" => l.currency,
      "source_name" => l.source_name,
      "source_url" => l.source_url
    }
  end

  defp overview_doc(docs, now) do
    year = imf_year()
    imf = Imf.document()

    rows =
      for d <- docs do
        rev = d["imf"]["revenue"][Integer.to_string(year)]
        exp = d["imf"]["expenditure"][Integer.to_string(year)]

        %{
          "code" => d["code"],
          "level" => d["level"],
          "kind" => d["profile"] && d["profile"]["kind"],
          "legislature" => d["profile"] && d["profile"]["legislature"],
          "revenue_pct" => rev,
          "expenditure_pct" => exp,
          "balance_pct" => if(is_number(rev) and is_number(exp), do: Float.round(rev - exp, 2)),
          "latest_law" => List.first(d["laws"]),
          "laws" => length(d["laws"])
        }
      end

    latest =
      docs
      |> Enum.flat_map(fn d -> Enum.map(d["laws"], &Map.put(&1, "country_code", d["code"])) end)
      |> Enum.sort_by(&{&1["last_date"] || "", &1["id"]}, :desc)
      |> Enum.take(12)

    %{
      "format" => @format,
      "built_at" => now,
      "year" => year,
      "imf" => %{"label" => imf["source"]["label"], "url" => imf["source"]["url"]},
      "countries" => rows,
      "latest" => latest,
      "counts" => %{
        "official" => Enum.count(rows, &(&1["level"] == "official")),
        "imf" => Enum.count(rows, &(&1["level"] == "imf"))
      }
    }
  end

  defp read(key), do: SyliAtlas.Market.Snapshots.read(key)

  defp put!(key, doc, now) do
    Repo.query!(
      """
      INSERT INTO snapshots (key, doc, inserted_at, updated_at) VALUES (?1, jsonb(?2), ?3, ?3)
      ON CONFLICT(key) DO UPDATE SET doc = excluded.doc, updated_at = excluded.updated_at
      """,
      [key, Jason.encode!(doc), now]
    )
  end

  defp stringify(attrs), do: Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
end
