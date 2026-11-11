defmodule SyliAtlasWeb.RecapController do
  @moduledoc """
  The country recap without an account (`SyliAtlas.Recaps`,
  `docs/recap.md`).

    * `new` / `create`: the form, also opened as a dialog from the footer
      (`assets/js/ui/recap.js`, which posts it as JSON).
    * `confirmation` / `confirm`: the link of the confirmation email. GET
      only shows the choices and a button (mail scanners open links); POST
      confirms.
    * `manage` / `update`: change the countries or the frequency.
    * `stop` / `unsubscribe`: GET asks, POST deletes the subscription,
      also the one-click POST of mail clients (RFC 8058).
  """
  use SyliAtlasWeb, :controller

  alias SyliAtlas.Accounts.User
  alias SyliAtlas.Recaps
  alias SyliAtlas.Recaps.Subscription
  alias SyliAtlasWeb.ClientIp

  @noindex %{noindex: true}

  def new(conn, params) do
    locale = conn.assigns.locale
    picked = params |> Map.get("pays", params["country"] || "") |> String.upcase() |> List.wrap()

    render_form(
      conn,
      locale,
      %{"countries" => picked, "frequency" => "weekly", "email" => ""},
      nil
    )
  end

  def create(conn, params) do
    locale = conn.assigns.locale
    attrs = form_attrs(params, locale)

    result = Recaps.subscribe(attrs, ip: ClientIp.key(conn))

    case {result, json?(conn)} do
      {{:ok, _sub}, true} ->
        json(conn, %{ok: true, email: User.normalize_email(attrs["email"])})

      {{:ok, _sub}, false} ->
        render(conn, :sent,
          locale: locale,
          page_title: gettext("Check your inbox"),
          email: User.normalize_email(attrs["email"]),
          seo: @noindex
        )

      {{:error, reason}, true} ->
        conn |> put_status(status(reason)) |> json(%{ok: false, error: message(reason)})

      {{:error, reason}, false} ->
        conn |> put_status(status(reason)) |> render_form(locale, attrs, message(reason))
    end
  end

  def confirmation(conn, %{"token" => token}) do
    case Recaps.resolve_confirmation(token) do
      {:ok, sub, choices} ->
        locale = choices["locale"] || sub.locale
        Gettext.put_locale(SyliAtlasWeb.Gettext, locale)

        render(conn, :confirmation,
          locale: locale,
          page_title: gettext("Confirm your recap"),
          token: token,
          email: sub.email,
          countries: names(choices["countries"], locale),
          frequency: choices["frequency"],
          done: false,
          seo: @noindex
        )

      :error ->
        invalid(conn)
    end
  end

  def confirm(conn, %{"token" => token}) do
    case Recaps.confirm(token) do
      {:ok, sub} ->
        Gettext.put_locale(SyliAtlasWeb.Gettext, sub.locale)

        render(conn, :confirmation,
          locale: sub.locale,
          page_title: gettext("Recap confirmed"),
          token: token,
          email: sub.email,
          countries: names(sub.countries, sub.locale),
          frequency: sub.frequency,
          manage: Recaps.manage_path(Recaps.manage_token(sub)),
          done: true,
          seo: @noindex
        )

      :error ->
        invalid(conn)
    end
  end

  def manage(conn, %{"token" => token}) do
    case Recaps.resolve_manage(token) do
      {:ok, sub} -> render_manage(conn, sub, token, nil, false)
      :error -> invalid(conn)
    end
  end

  def update(conn, %{"token" => token} = params) do
    with {:ok, sub} <- Recaps.resolve_manage(token) do
      attrs = %{
        "countries" => List.wrap(params["countries"]),
        "frequency" => params["frequency"]
      }

      case Recaps.update(sub, attrs) do
        {:ok, sub} ->
          render_manage(conn, sub, token, nil, true)

        {:error, _changeset} ->
          Gettext.put_locale(SyliAtlasWeb.Gettext, sub.locale)

          conn
          |> put_status(422)
          |> render_manage(
            %{sub | countries: attrs["countries"]},
            token,
            gettext("Choose between 1 and %{max} countries.", max: Subscription.max_countries()),
            false
          )
      end
    else
      :error -> invalid(conn)
    end
  end

  def stop(conn, %{"token" => token}) do
    case Recaps.resolve_manage(token) do
      {:ok, sub} ->
        Gettext.put_locale(SyliAtlasWeb.Gettext, sub.locale)

        render(conn, :stop,
          locale: sub.locale,
          page_title: gettext("Stop the recap"),
          token: token,
          email: sub.email,
          done: false,
          seo: @noindex
        )

      :error ->
        stopped_or_invalid(conn, token)
    end
  end

  def unsubscribe(conn, %{"token" => token}) do
    case Recaps.unsubscribe(token) do
      {:ok, locale} ->
        locale = locale || "fr"
        Gettext.put_locale(SyliAtlasWeb.Gettext, locale)

        render(conn, :stop,
          locale: locale,
          page_title: gettext("Stop the recap"),
          token: token,
          email: nil,
          done: true,
          seo: @noindex
        )

      :error ->
        invalid(conn)
    end
  end

  # A stop link opened again after the row was deleted: say it is done.
  defp stopped_or_invalid(conn, token) do
    case Recaps.unsubscribe(token) do
      {:ok, nil} ->
        render(conn, :stop,
          locale: "fr",
          page_title: gettext("Stop the recap"),
          token: token,
          email: nil,
          done: true,
          seo: @noindex
        )

      _ ->
        invalid(conn)
    end
  end

  defp render_form(conn, locale, attrs, error) do
    render(conn, :new,
      locale: locale,
      page_title: gettext("The recap of your countries"),
      regions: regions(locale),
      picked: MapSet.new(List.wrap(attrs["countries"])),
      frequency: attrs["frequency"] || "weekly",
      email: attrs["email"] || "",
      error: error,
      max: Subscription.max_countries(),
      seo: %{
        description:
          gettext(
            "Every Monday, the rating decisions, the stock exchange, the currency and the IMF landmarks of the African countries you choose. Free, without an account."
          )
      }
    )
  end

  defp render_manage(conn, sub, token, error, saved) do
    Gettext.put_locale(SyliAtlasWeb.Gettext, sub.locale)

    render(conn, :manage,
      locale: sub.locale,
      page_title: gettext("Change my recap"),
      token: token,
      email: sub.email,
      regions: regions(sub.locale),
      picked: MapSet.new(sub.countries),
      frequency: sub.frequency,
      error: error,
      saved: saved,
      max: Subscription.max_countries(),
      seo: @noindex
    )
  end

  defp invalid(conn) do
    conn
    |> put_status(404)
    |> render(:invalid,
      locale: conn.assigns[:locale] || "fr",
      page_title: gettext("Recap"),
      seo: @noindex
    )
  end

  defp form_attrs(params, locale) do
    %{
      "email" => params["email"] || "",
      "countries" => List.wrap(params["countries"]),
      "frequency" => params["frequency"] || "weekly",
      "locale" => locale
    }
  end

  defp json?(conn), do: Phoenix.Controller.get_format(conn) == "json"

  defp status(:rate_limited), do: 429
  defp status(:mail_not_configured), do: 503
  defp status(:not_sent), do: 502
  defp status(_changeset), do: 422

  defp message(:rate_limited),
    do: gettext("Too many requests for this address. Try again in an hour.")

  defp message(:mail_not_configured),
    do: gettext("The recap is not open yet: Syli Atlas cannot send emails for now.")

  defp message(:not_sent), do: gettext("The email could not be sent. Try again in a moment.")

  defp message(%Ecto.Changeset{} = cs) do
    cond do
      Keyword.has_key?(cs.errors, :email) ->
        gettext("Enter a valid email address.")

      Keyword.has_key?(cs.errors, :countries) ->
        gettext("Choose between 1 and %{max} countries.", max: Subscription.max_countries())

      true ->
        gettext("Check the form.")
    end
  end

  defp regions(locale) do
    countries = SyliAtlas.Geo.list_countries()

    for region <- SyliAtlas.Geo.list_regions() do
      list =
        countries
        |> Enum.filter(&(&1.region_code == region.code))
        |> Enum.map(&%{code: &1.code, name: SyliAtlas.Geo.Area.name(&1, locale)})
        |> Enum.sort_by(&String.normalize(&1.name, :nfd))

      %{code: region.code, name: SyliAtlas.Geo.Area.name(region, locale), countries: list}
    end
  end

  defp names(codes, locale) do
    Enum.map(List.wrap(codes), fn code ->
      case SyliAtlas.Geo.get_area_by_code(code) do
        nil -> code
        area -> SyliAtlas.Geo.Area.name(area, locale)
      end
    end)
  end
end
