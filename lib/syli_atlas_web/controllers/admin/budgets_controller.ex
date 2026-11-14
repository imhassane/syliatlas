defmodule SyliAtlasWeb.Admin.BudgetsController do
  @moduledoc """
  Admin: the budget laws to validate (read by the AI or typed by hand), the
  files to read (dropped here or fetched from the watched pages), and the
  54 countries' catalog (who votes, where laws are published, collection
  mode).
  """
  use SyliAtlasWeb, :controller

  alias SyliAtlas.Budgets
  alias SyliAtlas.Workers.{BudgetExtractWorker, BudgetFetchWorker}

  def index(conn, params) do
    render(conn, :index,
      page_title: "Admin · Budgets et lois",
      pending: Budgets.list_proposals("pending"),
      decided:
        (Budgets.list_proposals("approved", 30) ++ Budgets.list_proposals("rejected", 30))
        |> Enum.sort_by(& &1.reviewed_at, {:desc, DateTime})
        |> Enum.take(30),
      documents: Budgets.recent_documents(20),
      countries: countries(),
      extractor?: SyliAtlas.Budgets.Extractor.configured?(),
      model: SyliAtlas.Budgets.Extractor.model(),
      watched: length(Budgets.auto_profiles()),
      overview: Budgets.overview(),
      open: params["saisir"] == "1"
    )
  end

  def upload(conn, %{"d" => %{"country_code" => code, "file" => %Plug.Upload{} = upload} = d}) do
    with true <- valid_country?(code),
         {:ok, body} <- File.read(upload.path),
         {:ok, document, status} <-
           Budgets.store_document(code, "upload", %{
             body: body,
             filename: upload.filename,
             content_type: upload.content_type,
             url: blank(d["url"])
           }) do
      case status do
        :new ->
          BudgetExtractWorker.enqueue(document)

          message =
            if SyliAtlas.Budgets.Extractor.configured?(),
              do: "Fichier reçu : l'IA le lit, la proposition arrive dans la file.",
              else: "Fichier gardé. Pas de clé IA : saisissez la loi à la main."

          conn |> put_flash(:info, message) |> back()

        :duplicate ->
          conn |> put_flash(:error, "Ce fichier a déjà été reçu pour ce pays.") |> back()
      end
    else
      false ->
        conn |> put_flash(:error, "Pays inconnu.") |> back()

      {:error, :too_large} ->
        conn |> put_flash(:error, "Fichier trop lourd (32 Mo au plus).") |> back()

      {:error, reason} ->
        conn |> put_flash(:error, "Fichier refusé : #{inspect(reason)}") |> back()
    end
  end

  def upload(conn, _params),
    do: conn |> put_flash(:error, "Choisissez un pays et un fichier.") |> back()

  def reread(conn, %{"id" => id}) do
    document = Budgets.get_document!(id)
    {:ok, _} = BudgetExtractWorker.enqueue(document, again: true)
    conn |> put_flash(:info, "Nouvelle lecture demandée.") |> back()
  end

  def create(conn, %{"p" => attrs}) do
    case Budgets.propose(attrs) do
      {:ok, _} -> conn |> put_flash(:info, "Loi ajoutée à la file.") |> back()
      {:error, cs} -> conn |> put_flash(:error, "Saisie refusée : " <> errors(cs)) |> back()
    end
  end

  def approve(conn, %{"id" => id} = params) do
    case Budgets.approve(Budgets.get_proposal!(id), params["p"] || %{}) do
      {:ok, _law} ->
        conn |> put_flash(:info, "Loi publiée.") |> back()

      {:error, :already_reviewed} ->
        conn |> put_flash(:error, "Déjà traitée.") |> back()

      {:error, %Ecto.Changeset{} = cs} ->
        conn |> put_flash(:error, "Publication refusée : " <> errors(cs)) |> back()
    end
  end

  def reject(conn, %{"id" => id}) do
    case Budgets.reject(Budgets.get_proposal!(id)) do
      {:ok, _} -> conn |> put_flash(:info, "Proposition rejetée.") |> back()
      _ -> conn |> put_flash(:error, "Déjà traitée.") |> back()
    end
  end

  def watch(conn, _params) do
    {:ok, _} = %{} |> BudgetFetchWorker.new() |> Oban.insert()
    conn |> put_flash(:info, "Lecture des pages suivies lancée.") |> back()
  end

  def countries(conn, _params) do
    render(conn, :countries,
      page_title: "Admin · Budgets · pays",
      profiles: Budgets.list_profiles(),
      countries: Map.new(countries(), &{&1.code, &1}),
      overview: Budgets.overview()
    )
  end

  def country(conn, %{"code" => code}) do
    profile = Budgets.get_profile!(code)

    render(conn, :country,
      page_title: "Admin · Budgets · " <> code,
      profile: profile,
      form: Phoenix.Component.to_form(Budgets.change_profile(profile), as: :c),
      name: country_name(code)
    )
  end

  def update_country(conn, %{"code" => code, "c" => attrs}) do
    profile = Budgets.get_profile!(code)

    case Budgets.update_profile(profile, attrs) do
      {:ok, _} ->
        conn |> put_flash(:info, "Fiche enregistrée.") |> redirect(to: ~p"/admin/budgets/pays")

      {:error, cs} ->
        conn
        |> put_flash(:error, "Fiche refusée : " <> errors(cs))
        |> render(:country,
          page_title: "Admin · Budgets · " <> code,
          profile: profile,
          form: Phoenix.Component.to_form(%{cs | action: :update}, as: :c),
          name: country_name(code)
        )
    end
  end

  defp countries,
    do: SyliAtlas.Geo.list_countries() |> Enum.sort_by(&SyliAtlas.Geo.Area.name(&1, "fr"))

  defp valid_country?(code), do: Enum.any?(countries(), &(&1.code == code))

  defp country_name(code) do
    case SyliAtlas.Geo.get_area_by_code(code) do
      nil -> code
      a -> SyliAtlas.Geo.Area.name(a, "fr")
    end
  end

  defp blank(v) when v in [nil, ""], do: nil
  defp blank(v), do: String.trim(v)

  defp back(conn), do: redirect(conn, to: ~p"/admin/budgets")

  defp errors(%Ecto.Changeset{} = cs) do
    cs
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc -> String.replace(acc, "%{#{k}}", to_string(v)) end)
    end)
    |> Enum.map_join(", ", fn {field, msgs} -> "#{field} #{Enum.join(msgs, ", ")}" end)
  end

  defp errors(other), do: inspect(other)
end
