defmodule SyliAtlas.National do
  @moduledoc """
  Figures published by the countries themselves, shown next to the IMF's
  (decisions of 14 Nov. 2026, catalogue section 11):

    * every key figure twice: the IMF's (comparable, never touched) and the
      country's latest, each with its date, period, base year and source;
    * the sum of national figures for Africa: the country's counted figure
      of the year, else the IMF's of the same year (fallback), with its
      composition;
    * a figure is counted once verified: automatically when every check of
      `SyliAtlas.National.Verify` passes, else shown at once with the
      « being checked » badge and counted after a person's review.

  Pages read the `national` document (`SyliAtlas.National.Snapshot`),
  rebuilt after each change and after each IMF edition. The bundled file
  `priv/data/national_figures.json` holds the official domains of each
  country and the figures entered so far.
  """
  import Ecto.Query

  alias SyliAtlas.Repo
  alias SyliAtlas.National.{Figure, Snapshot, Verify}

  @key "national"
  @doc_key {__MODULE__, :document}
  @version_key {__MODULE__, :data_version}

  @doc "The bundled file: official domains, figures, rebasings."
  def bundled do
    Application.app_dir(:syli_atlas, "priv/data/national_figures.json")
    |> File.read!()
    |> Jason.decode!()
  end

  @doc "Countries whose official figures we follow (the bundled list), or nil for all."
  def tracked, do: bundled()["tracked"]

  @doc "Official domains of a country's sources (statistics, central bank, ministries)."
  def domains(code), do: get_in(bundled(), ["sources", code, "domains"]) || []

  @doc """
  Upserts the bundled figures and rebasings, then rebuilds the document.
  A figure a person already reviewed is never overwritten.
  """
  def seed! do
    data = bundled()

    # Only the countries we follow keep official figures (decisions of
    # 15 Nov. 2026): the others' figures leave, even reviewed ones.
    if tracked = data["tracked"] do
      Repo.delete_all(from f in Figure, where: f.country_code not in ^tracked)
    end

    for f <- data["figures"] || [] do
      case get(f["country_code"], f["indicator"], f["calendar_year"]) do
        %Figure{reviewed_at: %DateTime{}} -> :kept
        _ -> submit!(f, document: nil, second_read: nil, rebuild: false)
      end
    end

    SyliAtlas.National.Rebasings.seed!(data["rebasings"] || [])

    rebuild!()
    length(data["figures"] || [])
  end

  @doc """
  Records a figure after the automatic checks. `opts`: `:document` (the
  text of the source), `:second_read` (the second extraction),
  `:rebuild` (default true). Returns the figure.
  """
  def submit!(attrs, opts \\ []) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
    code = attrs["country_code"]
    year = attrs["calendar_year"]

    {status, checks} =
      Verify.run(attrs, %{
        document: opts[:document],
        second_read: opts[:second_read],
        imf: imf_value(code, attrs["indicator"], year),
        domains: domains(code),
        known_country?: counted_elsewhere?(code, attrs["indicator"], year)
      })

    figure =
      (get(code, attrs["indicator"], year) || %Figure{})
      |> Figure.changeset(
        Map.merge(attrs, %{
          "status" => status,
          "checks" => checks,
          "reviewed_at" => nil,
          "reviewed_by" => nil
        })
      )
      |> Repo.insert_or_update!()

    if Keyword.get(opts, :rebuild, true), do: rebuild!()
    figure
  end

  @doc "A person confirms a figure: it counts from now on."
  # A confirmed figure prepares its post for X and LinkedIn (SyliAtlas.Social).
  def verify!(%Figure{} = figure, who) do
    figure = review!(figure, "verified", who)
    SyliAtlas.Social.Drafts.safely(fn -> SyliAtlas.Social.Drafts.on_national_figure(figure) end)
    figure
  end

  @doc "A person rejects a figure: it leaves the public pages."
  def reject!(%Figure{} = figure, who), do: review!(figure, "rejected", who)

  defp review!(figure, status, who) do
    figure =
      figure
      |> Figure.changeset(%{
        "status" => status,
        "reviewed_at" => DateTime.utc_now() |> DateTime.truncate(:second),
        "reviewed_by" => who
      })
      |> Repo.update!()

    rebuild!()
    figure
  end

  def get!(id), do: Repo.get!(Figure, id)

  def get(code, indicator, year),
    do: Repo.get_by(Figure, country_code: code, indicator: indicator, calendar_year: year)

  @doc "Figures waiting for a person, oldest first."
  def pending do
    Repo.all(
      from f in Figure, where: f.status == "pending_review", order_by: [asc: f.inserted_at]
    )
  end

  @doc "Figures reviewed or counted, newest first."
  def decided(limit \\ 100) do
    Repo.all(
      from f in Figure,
        where: f.status != "pending_review",
        order_by: [desc: f.updated_at],
        limit: ^limit
    )
  end

  defp counted_elsewhere?(code, indicator, year) do
    Repo.exists?(
      from f in Figure,
        where:
          f.country_code == ^code and f.status in ^Figure.counted_statuses() and
            not (f.indicator == ^indicator and f.calendar_year == ^year)
    )
  end

  @doc "The IMF's value of a country, indicator and year, from its profile (or nil)."
  def imf_value(code, indicator, year) when is_integer(year) do
    case Repo.query!(
           "SELECT json_extract(doc, '$.series.' || ?2 || '[' || ?3 || ']') FROM profiles WHERE area_code = ?1",
           [code, indicator, year - 2015]
         ).rows do
      [[v]] when is_number(v) -> v * 1.0
      _ -> nil
    end
  end

  def imf_value(_code, _indicator, _year), do: nil

  @doc "Rebuilds the document the pages read."
  def rebuild! do
    # Alerts the IMF has caught up with close first (after an IMF edition).
    SyliAtlas.National.Rebasings.check_integration!()
    now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

    Repo.query!(
      """
      INSERT INTO snapshots (key, doc, inserted_at, updated_at) VALUES (?1, jsonb(?2), ?3, ?3)
      ON CONFLICT(key) DO UPDATE SET doc = excluded.doc, updated_at = excluded.updated_at
      """,
      [@key, Jason.encode!(Snapshot.build()), now]
    )

    :persistent_term.erase(@doc_key)
    refresh_data_version()
    :ok
  end

  @doc "The national document, or nil before the first build. Kept in memory once read."
  def document do
    case :persistent_term.get(@doc_key, :missing) do
      :missing -> load_document()
      :none -> nil
      doc -> doc
    end
  end

  defp load_document do
    doc =
      case Repo.query!("SELECT json(doc) FROM snapshots WHERE key = ?1", [@key]).rows do
        [[json]] when is_binary(json) -> Jason.decode!(json)
        _ -> nil
      end

    :persistent_term.put(@doc_key, doc || :none)
    doc
  end

  @doc "A country's entry: figures by indicator and year, the rebasing notice (or nil)."
  def for_country(nil, _code), do: nil
  def for_country(%{"countries" => countries}, code), do: countries[code]
  def for_country(_doc, _code), do: nil

  @doc """
  A country's rebasing notice (its latest published rebasing, active or
  taken in by the IMF), or nil. Any country, with or without figures.
  """
  def rebasing(%{"rebasings" => by_code}, code), do: by_code[code]
  def rebasing(_doc, _code), do: nil

  @doc "Every published rebasing, newest first."
  def rebasing_list(%{"rebasing_list" => list}), do: list
  def rebasing_list(_doc), do: []

  @doc "A country's figure for an indicator and year (or nil)."
  def figure(entry, indicator, year) do
    entry && get_in(entry, ["figures", indicator, Integer.to_string(year)])
  end

  @doc "The latest figure of a country for an indicator (or nil)."
  def latest(nil, _indicator), do: nil

  def latest(entry, indicator) do
    case entry["figures"][indicator] do
      nil -> nil
      by_year -> by_year |> Map.values() |> Enum.max_by(& &1["year"], fn -> nil end)
    end
  end

  @doc "The sum of national figures for Africa in a year (or nil)."
  def africa(nil, _year), do: nil
  def africa(doc, year), do: get_in(doc, ["africa", Integer.to_string(year)])

  @doc """
  The same sum for a group of countries (a region, a community): each
  member's counted official GDP of the year, else the IMF's. Read from the
  African rows of the document, so it costs no query. Nil without document.
  """
  def group(doc, codes, year) do
    case africa(doc, year) do
      nil ->
        nil

      %{"rows" => rows} ->
        members = MapSet.new(codes)
        rows = Enum.filter(rows, &MapSet.member?(members, &1["code"]))
        sum = fn key -> rows |> Enum.map(& &1[key]) |> Enum.filter(&is_number/1) |> Enum.sum() end
        imf_total = sum.("imf")
        national_total = sum.("retained")
        pending = Enum.filter(rows, &is_number(&1["pending"]))

        after_review =
          national_total + Enum.reduce(pending, 0, &(&1["pending"] - (&1["retained"] || 0) + &2))

        pct = fn a, b -> if is_number(b) and b != 0, do: Float.round((a / b - 1) * 100, 1) end

        %{
          "year" => year,
          "imf_total" => Float.round(imf_total * 1.0, 1),
          "national_total" => Float.round(national_total * 1.0, 1),
          "gap_pct" => pct.(national_total, imf_total),
          "counted" => Enum.count(rows, &(&1["source"] == "national")),
          "fallback" => Enum.count(rows, &(&1["source"] == "imf")),
          "pending" => Enum.map(pending, & &1["code"]),
          "after_review_total" => if(pending != [], do: Float.round(after_review * 1.0, 1)),
          "after_review_gap_pct" => if(pending != [], do: pct.(after_review, imf_total)),
          "members" => length(rows)
        }
    end
  end

  @doc "Is the stored document missing or of an older format than the code?"
  def stale? do
    case load_document() do
      %{"format" => format} -> format != Snapshot.format()
      _ -> true
    end
  end

  @doc "Short identifier of the national figures online (page ETags)."
  def data_version do
    case :persistent_term.get(@version_key, nil) do
      nil -> refresh_data_version()
      version -> version
    end
  end

  def refresh_data_version do
    version =
      case Repo.query!("SELECT updated_at FROM snapshots WHERE key = ?1", [@key]).rows do
        [[updated_at]] -> to_string(updated_at)
        _ -> "empty"
      end

    :persistent_term.put(@version_key, version)
    version
  end
end
