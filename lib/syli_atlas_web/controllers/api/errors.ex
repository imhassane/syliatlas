defmodule SyliAtlasWeb.Api.Errors do
  @moduledoc """
  One shape for every API error, with a stable code that programs can test:

      {"error": {"code": "unknown_area", "message": "…", "docs": "https://…/en/api#errors"}}

  Codes: `invalid_period`, `codes_required`, `unknown_indicator`,
  `unknown_area`, `not_found`, `rate_limited`.
  """
  import Plug.Conn

  @doc "Sends the error and returns the conn (not halted)."
  @spec send(Plug.Conn.t(), pos_integer(), String.t(), String.t()) :: Plug.Conn.t()
  def send(conn, status, code, message) do
    body =
      Jason.encode!(%{
        error: %{code: code, message: message, docs: docs_url(conn)}
      })

    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("access-control-allow-origin", "*")
    |> send_resp(status, body)
  end

  defp docs_url(conn) do
    locale = if conn.params["locale"] == "fr", do: "fr", else: "en"
    SyliAtlasWeb.Endpoint.url() <> SyliAtlasWeb.Paths.api(locale) <> "#" <> anchor(locale)
  rescue
    _ -> nil
  end

  defp anchor("fr"), do: "erreurs"
  defp anchor(_), do: "errors"
end
