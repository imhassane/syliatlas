defmodule SyliAtlas.National.Rebasings do
  @moduledoc """
  Rebasings of national accounts, for every African country (decisions of
  15 Nov. 2026):

    * the news watch (`SyliAtlas.National.Watch`) proposes them; a person
      publishes or rejects each one in the admin — nothing goes online by
      itself;
    * a published rebasing shows an alert on the country's pages (a chip in
      the header, a folded panel in the Economy tab), in its title and
      description, and on the page listing every rebasing;
    * the alert closes by itself once an IMF edition takes the rebasing in:
      after each edition, `check_integration!/0` compares the IMF's new GDP
      with the official figure, or with the IMF's GDP before the rebasing
      raised by at least half the announced revision.
  """
  import Ecto.Query

  alias SyliAtlas.Repo
  alias SyliAtlas.National
  alias SyliAtlas.National.{Figure, Rebasing}

  # Official figure within this gap of the IMF's: the IMF caught up.
  @caught_up_gap 5.0
  # Two articles about the same rebasing are this many days apart at most.
  @same_days 120

  def get!(id), do: Repo.get!(Rebasing, id)

  @doc "Published rebasings, newest first."
  def published do
    Repo.all(
      from r in Rebasing,
        where: r.status == "published",
        order_by: [desc: r.announced_on, asc: r.country_code]
    )
  end

  @doc "Proposals waiting for a person, newest first."
  def proposed do
    Repo.all(from r in Rebasing, where: r.status == "proposed", order_by: [desc: r.inserted_at])
  end

  @doc """
  A proposal of the watch. `:duplicate` when the country already has a
  rebasing (any status) to the same base or announced close to it.
  """
  def propose(attrs) do
    attrs = stringify(attrs)

    if duplicate?(attrs["country_code"], attrs["announced_on"], attrs["new_base"]) do
      :duplicate
    else
      %Rebasing{} |> Rebasing.proposal_changeset(attrs) |> Repo.insert()
    end
  end

  @doc "A rebasing typed in the admin: published at once (a person wrote it)."
  def create(attrs, who) do
    attrs = stringify(attrs) |> Map.put("origin", "manual")

    %Rebasing{}
    |> Rebasing.changeset(publication(attrs, who))
    |> Repo.insert()
    |> tap(&rebuild_if_ok/1)
    |> tap(&social_draft/1)
  end

  @doc "A person publishes a proposal, with the fields they completed."
  def publish(%Rebasing{} = r, attrs, who) do
    attrs = stringify(attrs) |> Map.merge(%{"country_code" => r.country_code})

    r
    |> Rebasing.changeset(publication(Map.merge(defaults(r), attrs), who))
    |> Repo.update()
    |> tap(&rebuild_if_ok/1)
    |> tap(&social_draft/1)
  end

  @doc "A person rejects a proposal (or withdraws a published rebasing)."
  def reject!(%Rebasing{} = r, who) do
    r
    |> Ecto.Changeset.change(status: "rejected", reviewed_by: who, reviewed_at: now())
    |> Repo.update!()
    |> tap(fn _ -> National.rebuild!() end)
  end

  @doc "A person states the IMF has taken the rebasing in (the automatic check missed it)."
  def mark_integrated!(%Rebasing{} = r, who) do
    r
    |> Ecto.Changeset.change(
      integrated_edition: current_edition() || r.imf_edition,
      integrated_on: Date.to_iso8601(Date.utc_today()),
      reviewed_by: who,
      reviewed_at: now()
    )
    |> Repo.update!()
    |> tap(fn _ -> National.rebuild!() end)
  end

  @doc "Upserts the rebasings of the bundled file (published, entered by hand)."
  def seed!(list) do
    for r <- list do
      attrs = stringify(r)

      current =
        Repo.get_by(Rebasing,
          country_code: attrs["country_code"],
          announced_on: attrs["announced_on"]
        )

      # A person's decision in the admin is kept.
      unless current && current.reviewed_at do
        (current || %Rebasing{})
        |> Rebasing.changeset(Map.merge(stamp(attrs), Map.put_new(attrs, "status", "published")))
        |> Repo.insert_or_update!()
      end
    end

    :ok
  end

  @doc """
  Closes the alerts the IMF has caught up with. Runs before each rebuild of
  the national document, so after each IMF edition. Returns the rebasings
  closed.
  """
  def check_integration! do
    edition = current_edition()

    for r <- published(),
        is_nil(r.integrated_edition),
        edition && r.imf_edition && edition > r.imf_edition,
        caught_up?(r) do
      r
      |> Ecto.Changeset.change(
        integrated_edition: edition,
        integrated_on: Date.to_iso8601(Date.utc_today())
      )
      |> Repo.update!()
    end
  end

  defp caught_up?(%Rebasing{} = r) do
    year = r.reference_year || default_year(r.announced_on)
    imf_now = National.imf_value(r.country_code, "gdp_usd_bn", year)
    official = latest_official(r.country_code)
    change = to_float(r.level_change_pct)
    before = to_float(r.imf_before)

    official_gap =
      with %Figure{} = f <- official,
           imf when is_number(imf) <-
             National.imf_value(f.country_code, f.indicator, f.calendar_year),
           v when is_number(v) <- to_float(f.value) do
        abs((v / imf - 1) * 100)
      else
        _ -> nil
      end

    cond do
      is_number(official_gap) ->
        official_gap < @caught_up_gap

      is_number(change) and is_number(before) and is_number(imf_now) and change > 0 ->
        imf_now >= before * (1 + change / 200)

      true ->
        false
    end
  end

  defp latest_official(code) do
    Repo.one(
      from f in Figure,
        where:
          f.country_code == ^code and f.indicator == "gdp_usd_bn" and
            f.status in ^Figure.counted_statuses(),
        order_by: [desc: f.calendar_year],
        limit: 1
    )
  end

  @doc "The IMF edition online, as its code (\"2026-10\"), or nil."
  def current_edition do
    case SyliAtlas.Sources.published_edition("imf_weo") do
      %{code: code} -> code
      _ -> nil
    end
  end

  @doc """
  The first edition of the IMF's World Economic Outlook after `date`: the
  IMF publishes it in April and October. Returns `{year, month}`.
  """
  def next_imf_edition(date \\ Date.utc_today()) do
    cond do
      date.month < 4 -> {date.year, 4}
      date.month < 10 -> {date.year, 10}
      true -> {date.year + 1, 4}
    end
  end

  @doc "An edition code (\"2027-04\") as `{year, month}`, or nil."
  def edition_month(code) when is_binary(code) do
    case String.split(code, "-") do
      [y, m] -> {String.to_integer(y), String.to_integer(m)}
      _ -> nil
    end
  rescue
    _ -> nil
  end

  def edition_month(_), do: nil

  # Year whose GDP the rebasing revises, by default the year before the
  # announcement (2026-11 → 2025).
  def default_year(<<y::binary-size(4), _::binary>>), do: String.to_integer(y) - 1
  def default_year(_), do: nil

  defp publication(attrs, who) do
    attrs
    |> stamp()
    |> Map.merge(%{"status" => "published", "reviewed_by" => who, "reviewed_at" => now()})
  end

  # The IMF's GDP of the reference year and its edition, as they are when
  # the rebasing goes online: what the next editions are compared with.
  defp stamp(attrs) do
    year =
      case attrs["reference_year"] do
        y when is_integer(y) -> y
        y when is_binary(y) and y != "" -> String.to_integer(y)
        _ -> default_year(attrs["announced_on"])
      end

    imf = year && National.imf_value(attrs["country_code"], "gdp_usd_bn", year)

    attrs
    |> Map.put("reference_year", year)
    |> Map.put_new("imf_before", imf && :erlang.float_to_binary(imf, decimals: 3))
    |> Map.put_new("imf_edition", current_edition())
  end

  defp defaults(r) do
    %{
      "announced_on" => r.announced_on,
      "old_base" => r.old_base,
      "new_base" => r.new_base,
      "level_change_pct" => r.level_change_pct,
      "source_name" => r.source_name,
      "source_url" => r.source_url,
      "reference_year" => r.reference_year
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp duplicate?(code, announced_on, new_base) when is_binary(code) do
    Repo.all(from r in Rebasing, where: r.country_code == ^code)
    |> Enum.any?(fn r ->
      same_base = is_binary(new_base) and norm(r.new_base) == norm(new_base)
      same_base or close?(r.announced_on, announced_on)
    end)
  end

  defp duplicate?(_code, _on, _base), do: false

  defp close?(a, b) do
    with {:ok, a} <- Date.from_iso8601(a || ""), {:ok, b} <- Date.from_iso8601(b || "") do
      abs(Date.diff(a, b)) <= @same_days
    else
      _ -> false
    end
  end

  defp norm(s), do: s |> to_string() |> String.replace(~r/[^0-9]/, "")

  defp rebuild_if_ok({:ok, _}), do: National.rebuild!()
  defp rebuild_if_ok(_), do: :ok

  defp stringify(attrs), do: Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp to_float(nil), do: nil
  defp to_float(s), do: SyliAtlas.National.Verify.to_float(s)

  # A published rebasing prepares its post for X and LinkedIn (SyliAtlas.Social).
  defp social_draft({:ok, r}),
    do: SyliAtlas.Social.Drafts.safely(fn -> SyliAtlas.Social.Drafts.on_rebasing(r) end)

  defp social_draft(_), do: :ok
end
