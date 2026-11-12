defmodule SyliAtlasWeb.ExportController do
  @moduledoc """
  An area's figures as a file: `/fr/pays/cote-d-ivoire/donnees.csv`,
  `…/donnees.xlsx`, `…/donnees.json`, with `?from=&to=` (the page's period)
  and, for CSV, `sep=comma|semicolon`.

  Made in the request from the precomputed document (SyliAtlasWeb.Export):
  a few kilobytes, no job queue. The route says the format and the kind of
  area (`assigns: %{format: …, kind: …}`); cache headers come from the
  :public_cache pipeline, like the page.
  """
  use SyliAtlasWeb, :controller

  alias SyliAtlas.Geo
  alias SyliAtlasWeb.{Export, NotFoundError, PageComponents, PublicData}
  alias SyliAtlasWeb.Api.V1

  def show(conn, %{"slug" => slug} = params) do
    locale = conn.assigns.locale
    area = Geo.get_area_by_slug(slug, locale) || raise NotFoundError
    if not kind?(area.kind, conn.assigns.kind), do: raise(NotFoundError)

    {from, to} = PageComponents.period(params)
    data = PublicData.area(area.code, from, to) || raise NotFoundError
    table = Export.table(data, area, locale, from, to)

    case conn.assigns.format do
      :csv ->
        sep = Export.separator(params["sep"], locale)

        send_file_body(
          conn,
          "text/csv; charset=utf-8",
          Export.filename(table) <> ".csv",
          Export.csv(table, sep)
        )

      :xlsx ->
        send_file_body(
          conn,
          "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
          Export.filename(table) <> ".xlsx",
          Export.xlsx(table)
        )

      :json ->
        # The very answer of the public API (/api/v1/areas/{code}), as a file.
        {:ok, answer} = V1.area(area.code, from, to)

        body =
          Jason.encode_to_iodata!(SyliAtlasWeb.Api.Spec.ordered(answer, "AreaAnswer"),
            pretty: true
          )

        send_file_body(conn, "application/json", Export.filename(table) <> ".json", body)
    end
  end

  defp kind?(kind, :country), do: kind == "country"
  defp kind?(kind, :region), do: kind in ["region", "continent"]

  defp send_file_body(conn, type, filename, body) do
    conn
    |> put_resp_content_type(type, nil)
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
    |> put_resp_header("x-robots-tag", "noindex")
    |> send_resp(200, body)
  end
end
