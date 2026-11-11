defmodule SyliAtlasWeb.Admin.UpdatesHTML do
  use SyliAtlasWeb, :html

  import SyliAtlasWeb.AdminComponents, only: [admin_shell: 1, admin_tabs: 1, admin_pager: 1]
  import SyliAtlasWeb.Admin.Format
  alias SyliAtlas.Admin.Jobs

  embed_templates "updates_html/*"

  def worker_label(worker), do: Jobs.worker_label(worker)
  def last_error(job), do: Jobs.last_error(job)
  def duration_ms(job), do: Jobs.duration_ms(job)

  @doc "What a finished job did, in a few words."
  def job_result(%{state: state} = job) when state in ["retryable", "discarded", "cancelled"],
    do: last_error(job) || "—"

  def job_result(%{args: args}) when map_size(args) == 0, do: "—"

  def job_result(%{args: args}) do
    args
    |> Enum.reject(fn {k, _} -> k in ["force"] end)
    |> Enum.map_join(" · ", fn {k, v} -> "#{k} #{inspect_arg(v)}" end)
  end

  defp inspect_arg(v) when is_binary(v), do: v
  defp inspect_arg(v), do: inspect(v)

  def source_status("active"), do: {"Active", "pill-ok"}
  def source_status("planned"), do: {"Prévue", "pill-info"}
  def source_status(s), do: {s, "pill-neutral"}

  def source_what("imf_weo"),
    do:
      "Croissance, PIB, PIB par habitant, inflation, dette, population, solde budgétaire, balance courante, chômage. Deux éditions par an."

  def source_what("world_bank_wdi"),
    do: "Ce que le FMI ne publie pas : électricité, scolarisation, espérance de vie."

  def source_what("un_wpp"),
    do: "Population détaillée et projections. Une révision tous les deux ans."

  def source_what(_), do: ""

  def edition_status("published"), do: {"En ligne", "pill-ok"}
  def edition_status("superseded"), do: {"Remplacée", "pill-neutral"}
  def edition_status("validated"), do: {"Validée", "pill-info"}
  def edition_status("failed"), do: {"Refusée", "pill-warn"}
  def edition_status(s), do: {s, "pill-neutral"}

  @doc "Fonctions JSON: names in French, with what they serve."
  def fn_label(:area_profile), do: {"area_profile", "fiche pays ou région · (code, de, à)"}
  def fn_label(:compare), do: {"compare", "comparaison · (codes, de, à)"}
  def fn_label(:ranking), do: {"ranking", "classement · (indicateur, de, à, région)"}
  def fn_label(:search), do: {"search", "recherche · (texte, langue)"}
  def fn_label(:map_countries), do: {"map_countries", "carte · (langue)"}
  def fn_label(name), do: {to_string(name), ""}

  def fn_status(:ok), do: {"Conforme", "pill-ok"}
  def fn_status(:limit), do: {"Limite", "pill-warn"}
  def fn_status(:over), do: {"Au-delà", "pill-warn"}

  @doc "Left offset and width (%) of the p50 → p99 bar on a 0 → 2 ms scale."
  def bar_style(%{p50: p50, p99: p99, status: status}) do
    left = min(p50 / 2000 * 100, 100.0)
    width = max(min((p99 - p50) / 2000 * 100, 100 - left), 1.0) * 1.0
    color = if status == :ok, do: "var(--accent)", else: "var(--signal)"
    "left: #{Float.round(left, 1)}%; width: #{Float.round(width, 1)}%; background: #{color}"
  end

  @doc "The steps of an import, from the timings kept in its stats."
  def steps(edition, after_job) do
    s = edition.stats || %{}
    ok? = edition.status in ["published", "superseded", "validated"]

    [
      {ok?, "Lire le fichier du FMI",
       "#{int(s["rows"])} lignes, #{s["indicators"] || "—"} indicateurs", s["parse_ms"]},
      {ok?, "Valider", validate_text(edition), s["validate_ms"]},
      {ok?, "Écrire dans SQLite", "#{int(s["values"])} valeurs, dans une seule transaction",
       s["write_ms"]},
      {edition.status in ["published", "superseded"], "Recalculer les documents",
       "#{s["profiles"] || "—"} documents : pays, régions, Afrique, monde", s["build_ms"]}
    ] ++ [after_step(after_job)]
  end

  defp validate_text(%{status: "failed", warnings: w}),
    do: "Refusée : #{Enum.join(Enum.take(w, 2), ", ")}"

  defp validate_text(%{warnings: w, stats: s}),
    do: "#{(s || %{})["countries"] || "—"} pays présents · #{length(w)} avertissement(s)"

  defp after_step(nil), do: {nil, "Prévenir les abonnés et mesurer", "Pas encore lancé", nil}

  defp after_step(job) do
    case job.state do
      "completed" ->
        {true, "Prévenir les abonnés et mesurer", "Alertes d'édition évaluées", nil}

      s when s in ["retryable", "discarded"] ->
        {false, "Prévenir les abonnés et mesurer", last_error(job) || "Échec", {:retry, job.id}}

      _ ->
        {nil, "Prévenir les abonnés et mesurer", "En cours", nil}
    end
  end

  @doc "An import warning in French: « Algérie : Chômage manquant 2020 – 2030 »."
  def warning_text(w, names) do
    case Regex.run(~r/^([A-Z_a-z]+): (\w+) missing for (\d{4})(?:-(\d{4}))?$/, w) do
      [_, code, key, from, to] ->
        "#{Map.get(names, code, code)} : #{indicator(key)} manquant #{from} – #{to}"

      [_, code, key, year] ->
        "#{Map.get(names, code, code)} : #{indicator(key)} manquant en #{year}"

      _ ->
        case Regex.run(~r/^([A-Z]+): no data in this edition$/, w) do
          [_, code] -> "#{Map.get(names, code, code)} : aucune donnée dans cette édition"
          _ -> w
        end
    end
  end

  def revision_value(v, true), do: decimal(v, 1)
  def revision_value(v, false) when abs(v) >= 100, do: int(round(v))
  def revision_value(v, false), do: decimal(v, 1)

  def revision_change(c, true), do: sign(c) <> decimal(abs(c), 1) <> " pt"
  def revision_change(c, false), do: sign(c) <> decimal(abs(c), 1) <> " %"

  defp sign(c) when c < 0, do: "−"
  defp sign(_), do: "+"
end
