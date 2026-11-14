defmodule SyliAtlasWeb.CspReportController do
  @moduledoc """
  Receives Content-Security-Policy violation reports (`SyliAtlasWeb.CSP`) and
  writes them to the logs, one line each: `csp violation directive=… blocked=…
  page=… source=…`.

  Both formats browsers send: `report-uri` (`application/csp-report`, one
  `{"csp-report": {...}}`) and the Reporting API (`application/reports+json`,
  a list of `{"type": "csp-violation", "body": {...}}`). Anyone can post
  here, so the body is capped, only a few short fields are logged, and each
  visitor address gets 30 reports a minute; the answer is always 204.
  """
  use SyliAtlasWeb, :controller

  require Logger

  @max_body 16_384
  @max_reports 10
  @per_minute 30

  def create(conn, _params) do
    key = "csp:" <> SyliAtlasWeb.ClientIp.key(conn)

    with {:allow, _} <- SyliAtlasWeb.RateLimit.hit(key, :timer.minutes(1), @per_minute),
         {:ok, reports} <- reports(conn) do
      reports |> Enum.take(@max_reports) |> Enum.each(&log/1)
    end

    send_resp(conn, 204, "")
  end

  # JSON bodies were parsed by Plug.Parsers; the report types pass through unread.
  defp reports(%Plug.Conn{body_params: %{"csp-report" => report}}), do: {:ok, [report]}

  defp reports(%Plug.Conn{body_params: %{"_json" => list}}) when is_list(list),
    do: {:ok, bodies(list)}

  defp reports(conn) do
    with {:ok, body, _conn} <- Plug.Conn.read_body(conn, length: @max_body),
         {:ok, decoded} <- Jason.decode(body) do
      case decoded do
        %{"csp-report" => report} -> {:ok, [report]}
        list when is_list(list) -> {:ok, bodies(list)}
        _ -> :error
      end
    else
      _ -> :error
    end
  end

  defp bodies(list) do
    for %{"type" => "csp-violation", "body" => body} when is_map(body) <- list, do: body
  end

  defp log(report) when is_map(report) do
    fields = [
      directive:
        field(report, ["effectiveDirective", "effective-directive", "violated-directive"]),
      blocked: field(report, ["blockedURL", "blocked-uri"]),
      page: field(report, ["documentURL", "document-uri"]),
      source:
        Enum.join(
          Enum.reject(
            [
              field(report, ["sourceFile", "source-file"]),
              field(report, ["lineNumber", "line-number"])
            ],
            &(&1 == "-")
          ),
          ":"
        ),
      sample: field(report, ["sample", "script-sample"])
    ]

    Logger.warning(
      "csp violation " <> Enum.map_join(fields, " ", fn {k, v} -> "#{k}=#{inspect(v)}" end)
    )
  end

  defp log(_), do: :ok

  defp field(report, names) do
    case Enum.find_value(names, &report[&1]) do
      nil -> "-"
      value -> value |> to_string() |> String.slice(0, 200)
    end
  end
end
