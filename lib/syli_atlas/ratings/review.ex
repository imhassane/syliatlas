defmodule SyliAtlas.Ratings.Review do
  @moduledoc """
  The validation queue. Every new decision, whether found by the news watch
  or typed by hand, waits here as a `Proposal` with automatic warnings.
  A person approves it with the link to the agency's own release, which
  becomes the published source (never the article, never the AI).
  """
  import Ecto.Query

  alias SyliAtlas.Repo
  alias SyliAtlas.Ratings
  alias SyliAtlas.Ratings.{Proposal, Rating, Scale}

  # The agency's own site, where its releases are published.
  @agency_hosts %{
    "sp" => ["spglobal.com"],
    "moodys" => ["moodys.com"],
    "fitch" => ["fitchratings.com"],
    "afcra" => []
  }

  @moodys ~r/^(Aaa|Aa[123]|A[123]|Baa[123]|Ba[123]|B[123]|Caa[123]|Ca)$/

  @doc "Records a proposal with its warnings. A duplicate of a pending one is an error."
  def propose(attrs) do
    changeset = Proposal.changeset(%Proposal{}, attrs)

    changeset
    |> Ecto.Changeset.put_change(:warnings, warnings(Ecto.Changeset.apply_changes(changeset)))
    |> Repo.insert()
  end

  def list(status, limit \\ 100) do
    Repo.all(
      from p in Proposal,
        where: p.status == ^status,
        order_by: [desc: p.updated_at, desc: p.id],
        limit: ^limit
    )
  end

  def count_pending, do: Repo.aggregate(from(p in Proposal, where: p.status == "pending"), :count)

  def get!(id), do: Repo.get!(Proposal, id)

  @doc """
  Publishes a pending proposal, after the reviewer's corrections in `attrs`.
  Requires the link to the agency's release.
  """
  def approve(%Proposal{status: "pending"} = proposal, attrs) do
    changeset = Proposal.changeset(proposal, attrs)
    p = Ecto.Changeset.apply_changes(changeset)

    with :ok <- check_source(p.agency, p.source_url),
         true <- changeset.valid? || {:error, changeset} do
      Repo.transaction(fn ->
        rating =
          Ratings.put_rating!(%{
            country_code: p.country_code,
            agency: p.agency,
            rating: p.rating,
            outlook: p.outlook,
            action_date: p.action_date,
            action_type: p.action_type,
            source_url: p.source_url,
            needs_check: false,
            reviewed_at: now()
          })

        changeset
        |> Ecto.Changeset.change(status: "approved", reviewed_at: now())
        |> Repo.update!()

        rating
      end)
      |> tap(fn
        {:ok, _} -> Ratings.rebuild!()
        _ -> :ok
      end)
    end
  end

  def approve(%Proposal{}, _attrs), do: {:error, :already_reviewed}

  def reject(%Proposal{status: "pending"} = proposal),
    do: proposal |> Proposal.review_changeset("rejected") |> Repo.update()

  def reject(%Proposal{}), do: {:error, :already_reviewed}

  @doc "Published decisions still marked « to check », oldest first."
  def to_check do
    Repo.all(
      from r in Rating,
        where: r.needs_check == true,
        order_by: [asc: r.country_code, asc: r.agency]
    )
  end

  @doc "Marks a published decision as checked, with corrections (rating, outlook, date, source)."
  def mark_checked(%Rating{} = rating, attrs) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
    agency = rating.agency
    source = blank_to_nil(attrs["source_url"]) || rating.source_url

    with :ok <- check_source(agency, source) do
      rating
      |> Rating.changeset(
        attrs
        |> Map.take(~w(rating outlook action_date action_type))
        |> Map.reject(fn {_k, v} -> v in [nil, ""] end)
        |> Map.merge(%{"source_url" => source, "needs_check" => false, "reviewed_at" => now()})
      )
      |> Repo.update()
      |> tap(fn
        {:ok, _} -> Ratings.rebuild!()
        _ -> :ok
      end)
    end
  end

  @doc "Is the link on the agency's own site? Required to publish."
  def check_source(agency, url) do
    hosts = Map.get(@agency_hosts, agency, [])

    case url && URI.parse(url) do
      %URI{scheme: "https", host: host} when is_binary(host) ->
        if hosts == [] or Enum.any?(hosts, &(host == &1 or String.ends_with?(host, "." <> &1))),
          do: :ok,
          else: {:error, :not_agency_source}

      _ ->
        {:error, :missing_source}
    end
  end

  @doc """
  Automatic checks on a proposal, against the current rating of the agency.
  Each warning is a code shown in the admin; none blocks a publication.
  """
  def warnings(%Proposal{} = p) do
    doc = Ratings.document()
    entry = Ratings.for_country(doc, p.country_code)
    current = entry && Enum.find(entry["agencies"], &(&1["agency"] == p.agency))
    score = Scale.score(p.rating)
    date = p.action_date || ""

    [
      {is_nil(entry), "unknown_country"},
      {scale_mismatch?(p.agency, p.rating), "wrong_scale"},
      {current && current["rating"] == p.rating && current["outlook"] == p.outlook,
       "same_as_current"},
      {current && score && abs(score - current["score"]) >= 3, "big_jump"},
      {current && score && direction_mismatch?(p.action_type, score, current["score"]),
       "type_mismatch"},
      {current && date != "" && date < (current["action_date"] || ""), "older_than_current"},
      {date > Date.to_iso8601(Date.utc_today()), "future_date"},
      {date == "", "no_date"}
    ]
    |> Enum.filter(fn {flag, _} -> flag == true end)
    |> Enum.map(fn {_, code} -> code end)
  end

  defp scale_mismatch?("moodys", rating), do: not Regex.match?(@moodys, rating || "")

  defp scale_mismatch?(agency, rating) when agency in ["sp", "fitch"],
    do: Regex.match?(@moodys, rating || "")

  defp scale_mismatch?(_agency, _rating), do: false

  defp direction_mismatch?("upgrade", score, current), do: score <= current
  defp direction_mismatch?("downgrade", score, current), do: score >= current

  defp direction_mismatch?(type, score, current)
       when type in ["affirmed", "outlook_up", "outlook_down", "outlook"],
       do: score != current

  defp direction_mismatch?(_type, _score, _current), do: false

  defp blank_to_nil(v) when v in [nil, ""], do: nil
  defp blank_to_nil(v), do: String.trim(v)

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
