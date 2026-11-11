defmodule SyliAtlasWeb.UnsubscribeController do
  @moduledoc """
  The unsubscribe links of the emails. GET shows what will stop and asks
  (mail scanners open links); POST stops it, also the one-click POST mail
  clients send (RFC 8058), which carries no CSRF token: the signed token in
  the URL is the proof.
  """
  use SyliAtlasWeb, :controller

  alias SyliAtlas.Accounts.Unsubscribe

  def show(conn, %{"token" => token}) do
    case Unsubscribe.resolve(token) do
      {:ok, scope, user, alert} ->
        Gettext.put_locale(SyliAtlasWeb.Gettext, user.locale)

        render(conn, :show,
          locale: user.locale,
          page_title: gettext("Unsubscribe"),
          token: token,
          scope: scope,
          alert: alert,
          done: false,
          seo: %{noindex: true}
        )

      :error ->
        invalid(conn)
    end
  end

  def create(conn, %{"token" => token}) do
    case Unsubscribe.apply(token) do
      {:ok, scope, user} ->
        Gettext.put_locale(SyliAtlasWeb.Gettext, user.locale)

        render(conn, :show,
          locale: user.locale,
          page_title: gettext("Unsubscribe"),
          token: token,
          scope: scope,
          alert: nil,
          done: true,
          seo: %{noindex: true}
        )

      :error ->
        invalid(conn)
    end
  end

  defp invalid(conn) do
    conn
    |> put_status(404)
    |> render(:show,
      locale: "fr",
      page_title: gettext("Unsubscribe"),
      token: nil,
      scope: nil,
      alert: nil,
      done: false,
      seo: %{noindex: true}
    )
  end
end
