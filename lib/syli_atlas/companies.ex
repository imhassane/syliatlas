defmodule SyliAtlas.Companies do
  @moduledoc """
  The main companies of a product (mines, producers, state companies),
  shown on the product pages. They come from `priv/data/companies.json`,
  written by hand with a source page for each, and from administrators.

  Nothing is shown until its source confirms it: every line is checked
  against its source page by SyliAtlas.Companies.Verifier (an AI reading
  the page, under rules the code enforces), when it is added, then every
  30 days. A line the check does not confirm is hidden at once; a line
  not confirmed for 90 days is hidden too. The AI never adds a company:
  it can only confirm or hide.
  """
  import Ecto.Query
  require Logger

  alias SyliAtlas.Repo
  alias SyliAtlas.Companies.{Company, Verifier}

  @recheck_days 30
  @valid_days 90

  def seed_path, do: Application.app_dir(:syli_atlas, "priv/data/companies.json")

  @doc "Companies shown for a product: confirmed by their source within 90 days."
  def published(product) do
    since = DateTime.add(DateTime.utc_now(), -@valid_days, :day)

    Repo.all(
      from c in Company,
        where: c.product == ^product and c.status == "published" and c.verified_at >= ^since,
        order_by: [c.position, c.name]
    )
  end

  def list_all do
    Repo.all(from c in Company, order_by: [c.product, c.position, c.name])
  end

  def get!(id), do: Repo.get!(Company, id)

  @doc """
  Adds the companies of the seed file that are not in the base yet, and
  updates those whose facts changed in the file (they are checked again).
  Withdrawn companies stay withdrawn.
  """
  def sync_seed!(path \\ seed_path()) do
    rows = if File.exists?(path), do: path |> File.read!() |> Jason.decode!(), else: []
    existing = Map.new(list_all(), &{{&1.product, &1.name}, &1})

    rows
    |> Enum.with_index()
    |> Enum.reduce(%{added: 0, changed: 0}, fn {attrs, i}, acc ->
      attrs = Map.put_new(attrs, "position", i)

      case existing[{attrs["product"], attrs["name"]}] do
        nil ->
          case %Company{} |> Company.changeset(attrs) |> Repo.insert() do
            {:ok, _} ->
              %{acc | added: acc.added + 1}

            {:error, cs} ->
              Logger.error("companies seed: #{attrs["name"]} #{inspect(cs.errors)}")
              acc
          end

        %Company{status: "withdrawn"} ->
          acc

        company ->
          cs = Company.changeset(company, attrs)

          if facts_changed?(cs) do
            cs
            |> Ecto.Changeset.put_change(:status, "pending")
            |> Ecto.Changeset.put_change(:checked_at, nil)
            |> Repo.update!()

            %{acc | changed: acc.changed + 1}
          else
            if cs.changes != %{}, do: Repo.update!(cs)
            acc
          end
      end
    end)
  end

  defp facts_changed?(cs),
    do: Enum.any?(~w(country kind owners source_url name)a, &Map.has_key?(cs.changes, &1))

  @doc "Companies to check now: never checked, or checked more than 30 days ago."
  def due(limit \\ 25) do
    before = DateTime.add(DateTime.utc_now(), -@recheck_days, :day)

    Repo.all(
      from c in Company,
        where: c.status != "withdrawn" and (is_nil(c.checked_at) or c.checked_at < ^before),
        order_by: [asc_nulls_first: c.checked_at, asc: c.id],
        limit: ^limit
    )
  end

  @doc "Hides the published companies not confirmed for 90 days. Returns how many."
  def expire! do
    since = DateTime.add(DateTime.utc_now(), -@valid_days, :day)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {n, _} =
      Repo.update_all(
        from(c in Company, where: c.status == "published" and c.verified_at < ^since),
        set: [status: "hidden", note: "non confirmée depuis 90 jours", updated_at: now]
      )

    n
  end

  @doc """
  Checks one company against its source and records the result:
  published when confirmed, hidden otherwise. When nothing can be
  concluded (no key, the AI unreachable), only the note changes.
  """
  def check!(company, verifier \\ &Verifier.check/1)

  def check!(%Company{status: "withdrawn"} = c, _verifier), do: c

  def check!(%Company{} = c, verifier) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs =
      case verifier.(c) do
        {:confirmed, excerpt} ->
          %{status: "published", excerpt: excerpt, note: nil, checked_at: now, verified_at: now}

        {:rejected, reason} ->
          %{status: "hidden", note: String.slice(reason, 0, 250), checked_at: now}

        {:error, reason} ->
          %{note: "vérification impossible : #{inspect(reason) |> String.slice(0, 200)}"}
      end

    c |> Company.check_changeset(attrs) |> Repo.update!()
  end

  @doc "An administrator removes a company: shown nowhere, never checked again."
  def withdraw!(%Company{} = c),
    do:
      c
      |> Company.check_changeset(%{status: "withdrawn", note: "retirée par un administrateur"})
      |> Repo.update!()

  @doc "An administrator asks for a new check (a hidden or withdrawn company)."
  def recheck!(%Company{} = c) do
    c
    |> Ecto.Changeset.change(status: "pending", checked_at: nil, note: nil)
    |> Repo.update!()
  end

  def create(attrs), do: %Company{} |> Company.changeset(attrs) |> Repo.insert()

  @doc "Counts by status, and the companies hidden since `since` (for the daily email)."
  def summary(since) do
    counts =
      Repo.all(from c in Company, group_by: c.status, select: {c.status, count(c.id)})
      |> Map.new()

    hidden =
      Repo.all(
        from c in Company,
          where: c.status == "hidden" and c.checked_at >= ^since,
          order_by: [desc: c.checked_at]
      )

    confirmed =
      Repo.one(
        from c in Company,
          where: c.status == "published" and c.verified_at >= ^since,
          select: count(c.id)
      )

    %{counts: counts, hidden: hidden, confirmed: confirmed}
  end
end
