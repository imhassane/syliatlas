defmodule SyliAtlasWeb.Admin.CompaniesController do
  @moduledoc """
  Admin « Entreprises »: the companies of the product pages, their last
  check and its reason. An administrator adds a company (it is shown once
  its source confirms it), asks for a check now, or withdraws a company.
  """
  use SyliAtlasWeb, :controller

  alias SyliAtlas.Companies
  alias SyliAtlas.Workers.CompaniesWorker

  def index(conn, params) do
    rows = Companies.list_all()

    render(conn, :index,
      page_title: "Admin · Entreprises",
      rows: rows,
      counts: Enum.frequencies_by(rows, & &1.status),
      ready: SyliAtlas.Companies.Verifier.configured?(),
      adding: params["ajouter"] == "1",
      countries:
        SyliAtlas.Geo.list_countries()
        |> Enum.map(&{&1.code, &1.name_fr})
        |> Enum.sort_by(&SyliAtlas.Geo.Area.normalize(elem(&1, 1)))
    )
  end

  def create(conn, %{"company" => attrs}) do
    case Companies.create(attrs) do
      {:ok, c} ->
        {:ok, _} = %{"id" => c.id} |> CompaniesWorker.new() |> Oban.insert()

        conn
        |> put_flash(:info, "Ajoutée : elle sera affichée dès que sa source la confirme.")
        |> back()

      {:error, cs} ->
        conn
        |> put_flash(:error, "Refusée : #{errors(cs)}")
        |> redirect(to: ~p"/admin/entreprises?ajouter=1")
    end
  end

  def check(conn, %{"id" => id}) do
    c = id |> Companies.get!() |> Companies.recheck!()
    {:ok, _} = %{"id" => c.id} |> CompaniesWorker.new() |> Oban.insert()
    conn |> put_flash(:info, "Vérification lancée : résultat dans une minute.") |> back()
  end

  def check_due(conn, _params) do
    {:ok, _} = %{} |> CompaniesWorker.new() |> Oban.insert()
    conn |> put_flash(:info, "Vérification des lignes dues lancée.") |> back()
  end

  def withdraw(conn, %{"id" => id}) do
    id |> Companies.get!() |> Companies.withdraw!()
    conn |> put_flash(:info, "Retirée : elle n'apparaît plus et ne sera plus vérifiée.") |> back()
  end

  defp errors(%Ecto.Changeset{} = cs) do
    cs
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc -> String.replace(acc, "%{#{k}}", to_string(v)) end)
    end)
    |> Enum.map_join(", ", fn {field, msgs} -> "#{field} #{Enum.join(msgs, ", ")}" end)
  end

  defp back(conn), do: redirect(conn, to: ~p"/admin/entreprises")
end
