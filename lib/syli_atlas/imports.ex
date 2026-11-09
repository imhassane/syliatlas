defmodule SyliAtlas.Imports do
  @moduledoc """
  Brings a new IMF edition online: store, validate, publish, rebuild the
  documents, then let the SEO and alert jobs run. Each step is timed and
  kept in the edition's stats for the admin.
  """
  require Logger
  alias SyliAtlas.{Geo, Profiles, Repo, Sources}
  alias SyliAtlas.Imports.{ImfParser, Validator}

  @source "imf_weo"

  @doc "Imports a payload already fetched (live or from the bundled snapshot)."
  def import_payload(label, payload, opts \\ []) do
    source = Sources.get_source!(@source)

    with {:ok, code} <- ImfParser.edition_code(label) do
      edition =
        Sources.get_edition(source.id, code) ||
          Sources.create_edition!(%{source_id: source.id, code: code, label: label})

      if edition.status == "published" and not Keyword.get(opts, :force, false) do
        {:ok, :already_published, edition}
      else
        run(edition, payload)
      end
    end
  end

  @doc "Imports the snapshot shipped in priv/data, so the site works without network."
  def import_snapshot!(file \\ "imf_weo_2026_10.json") do
    payload =
      Application.app_dir(:syli_atlas, "priv/data/" <> file) |> File.read!() |> Jason.decode!()

    import_payload(payload["edition_label"], payload)
  end

  defp run(edition, payload) do
    areas = Geo.list_areas()
    imf_to_area = for a <- areas, a.imf_code, into: %{}, do: {a.imf_code, a.code}
    countries = Enum.filter(areas, &(&1.kind == "country"))

    {rows, t_parse} = timed(fn -> ImfParser.rows(payload, imf_to_area) end)
    {validation, t_validate} = timed(fn -> Validator.validate(rows, countries) end)

    case validation do
      {:error, errors, warnings} ->
        Sources.update_edition!(edition, %{status: "failed", warnings: errors ++ warnings})
        Logger.error("IMF edition #{edition.code} rejected: #{Enum.join(errors, ", ")}")
        {:error, errors}

      {:ok, stats, warnings} ->
        {_, t_write} = timed(fn -> Sources.insert_observations!(edition, rows) end)

        edition =
          Sources.update_edition!(edition, %{
            status: "validated",
            fetched_at: now(),
            warnings: warnings,
            checksum: checksum(payload)
          })

        {count, t_build} = timed(fn -> publish!(edition) end)

        steps = %{
          "parse_ms" => t_parse,
          "validate_ms" => t_validate,
          "write_ms" => t_write,
          "build_ms" => t_build,
          "profiles" => count
        }

        edition = Sources.update_edition!(edition, %{stats: Map.merge(stats, steps)})
        SyliAtlas.Events.broadcast_edition_published(edition)
        {:ok, :published, edition}
    end
  end

  defp publish!(edition) do
    Repo.transaction(fn ->
      import Ecto.Query

      Repo.update_all(
        from(e in Sources.Edition,
          where:
            e.source_id == ^edition.source_id and e.status == "published" and e.id != ^edition.id
        ),
        set: [status: "superseded"]
      )

      Sources.update_edition!(edition, %{status: "published", published_at: now()})
    end)

    Profiles.rebuild!(edition)
  end

  defp timed(fun) do
    {us, result} = :timer.tc(fun)
    {result, div(us, 1000)}
  end

  defp checksum(payload),
    do: :crypto.hash(:sha256, :erlang.term_to_binary(payload)) |> Base.encode16(case: :lower)

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
