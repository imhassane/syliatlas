defmodule SyliAtlasWeb.AccountController do
  @moduledoc """
  The member's space: favourites, alerts, security (passkeys, sessions,
  email preferences). `me/2` tells public pages, which carry no session,
  who is signed in and what they follow.
  """
  use SyliAtlasWeb, :controller

  alias SyliAtlas.{Accounts, Geo}
  alias SyliAtlas.Accounts.Favorite
  alias SyliAtlasWeb.Paths

  def favorites(conn, _params) do
    user = conn.assigns.current_user
    alerts = Accounts.Alerts.counts_by_area(user)

    render(conn, :favorites,
      page_title: gettext("Favourites"),
      tab: :favorites,
      favorites:
        user |> Accounts.list_favorites() |> Enum.map(&describe(&1, conn.assigns.locale)),
      alert_counts: alerts,
      seo: %{noindex: true}
    )
  end

  def alerts(conn, params) do
    market = %Accounts.Alert{
      kind: if(params["ticker"], do: "price_above", else: "session_move"),
      exchange_code: params["exchange"],
      ticker: params["ticker"]
    }

    render_alerts(conn,
      form: to_alert_form(%Accounts.Alert{area_code: params["area"]}),
      market_form: to_alert_form(market)
    )
  end

  defp render_alerts(conn, assigns) do
    render(
      conn,
      :alerts,
      [
        page_title: gettext("Alerts"),
        tab: :alerts,
        alerts: Accounts.list_alerts(conn.assigns.current_user),
        countries: Geo.list_countries(),
        exchanges: exchanges(),
        seo: %{noindex: true}
      ] ++ assigns
    )
  end

  defp to_alert_form(%Accounts.Alert{} = alert),
    do: Phoenix.Component.to_form(Accounts.change_alert(alert), as: :alert)

  # Exchanges with published data, for market alerts.
  defp exchanges do
    case SyliAtlas.Market.public?() && SyliAtlas.Market.overview() do
      %{"exchanges" => list} ->
        Enum.map(list, &{&1["exchange"]["code"], &1["exchange"]["short_name"]})

      _ ->
        []
    end
  end

  def security(conn, _params) do
    user = conn.assigns.current_user

    render(conn, :security,
      page_title: pgettext("account", "Security"),
      tab: :security,
      passkeys: Accounts.list_passkeys(user),
      manage?: Accounts.may_manage_passkeys?(user, conn.assigns.current_session),
      code_sent?: get_session(conn, :security_code) != nil,
      sessions: Accounts.list_sessions(user),
      seo: %{noindex: true}
    )
  end

  # Favourites ------------------------------------------------------------

  @doc "Follows or stops following; JSON for the stars of public pages, else back."
  def toggle_favorite(conn, %{"kind" => kind, "ref" => ref} = params) do
    user = conn.assigns.current_user

    result =
      if params["on"] in ["false", false],
        do: Accounts.remove_favorite(user, kind, ref),
        else: Accounts.add_favorite(user, kind, ref)

    case {result, get_format(conn)} do
      {:ok, "json"} -> json(conn, %{favorites: Accounts.favorite_keys(user)})
      {{:error, reason}, "json"} -> conn |> put_status(422) |> json(%{error: reason})
      {_, _} -> redirect(conn, to: Paths.account(user.locale))
    end
  end

  # Alerts ----------------------------------------------------------------

  def create_alert(conn, %{"alert" => attrs}) do
    user = conn.assigns.current_user

    case Accounts.create_alert(user, attrs) do
      {:ok, _} ->
        conn |> put_flash(:info, gettext("Alert created.")) |> back(:alerts)

      {:error, :too_many_alerts} ->
        conn |> put_flash(:error, gettext("50 alerts at most.")) |> back(:alerts)

      {:error, changeset} ->
        form = Phoenix.Component.to_form(changeset, as: :alert)

        if Ecto.Changeset.get_field(changeset, :kind) in Accounts.Alert.market_kinds(),
          do: render_alerts(conn, form: to_alert_form(%Accounts.Alert{}), market_form: form),
          else:
            render_alerts(conn,
              form: form,
              market_form: to_alert_form(%Accounts.Alert{kind: "session_move"})
            )
    end
  end

  def update_alert(conn, %{"id" => id} = params) do
    user = conn.assigns.current_user

    with %Accounts.Alert{} = alert <- Accounts.get_alert(user, id),
         {:ok, _} <- Accounts.update_alert(alert, Map.take(params, ["active", "frequency"])) do
      back(conn, :alerts)
    else
      _ -> conn |> put_flash(:error, gettext("This alert could not be changed.")) |> back(:alerts)
    end
  end

  def delete_alert(conn, %{"id" => id}) do
    Accounts.delete_alert(conn.assigns.current_user, id)
    conn |> put_flash(:info, gettext("Alert deleted.")) |> back(:alerts)
  end

  # Security --------------------------------------------------------------

  def delete_passkey(conn, %{"id" => id}) do
    %{current_user: user, current_session: session} = conn.assigns

    case Accounts.remove_passkey(user, session, id) do
      :ok ->
        conn |> put_flash(:info, gettext("Passkey removed.")) |> back(:security)

      {:error, :proof_required} ->
        proof_required(conn)

      {:error, _} ->
        back(conn, :security)
    end
  end

  def rename_passkey(conn, %{"id" => id, "passkey" => %{"name" => name}}) do
    %{current_user: user, current_session: session} = conn.assigns

    case Accounts.rename_passkey(user, session, id, name) do
      {:ok, _} -> conn |> put_flash(:info, gettext("Passkey renamed.")) |> back(:security)
      {:error, :proof_required} -> proof_required(conn)
      {:error, _} -> back(conn, :security)
    end
  end

  @doc "Sends a code to the account's address, to manage its passkeys."
  def request_security_code(conn, _params) do
    user = conn.assigns.current_user

    case Accounts.request_code(user.email, user.locale) do
      {:ok, code_id, _email} ->
        conn
        |> put_session(:security_code, code_id)
        |> put_flash(:info, gettext("A code was sent to your address."))
        |> back(:security)

      {:error, _} ->
        conn
        |> put_flash(:error, gettext("The code could not be sent. Try again in a few minutes."))
        |> back(:security)
    end
  end

  def confirm_security_code(conn, %{"code" => code}) do
    %{current_user: user, current_session: session} = conn.assigns

    with id when id != nil <- get_session(conn, :security_code),
         {:ok, _session} <- Accounts.confirm_with_code(id, user, session, code) do
      conn
      |> Plug.Conn.delete_session(:security_code)
      |> put_flash(:info, gettext("Confirmed: you can manage your passkeys for 10 minutes."))
      |> back(:security)
    else
      {:error, reason} when reason in [:expired, :too_many_attempts, :already_used] ->
        conn
        |> Plug.Conn.delete_session(:security_code)
        |> put_flash(:error, gettext("This code no longer works. Ask for a new one."))
        |> back(:security)

      _ ->
        conn
        |> put_flash(:error, gettext("Wrong code. Check the last email received."))
        |> back(:security)
    end
  end

  defp proof_required(conn) do
    conn
    |> put_flash(:error, gettext("Confirm with an email code first."))
    |> back(:security)
  end

  def delete_session(conn, %{"id" => id}) do
    Accounts.revoke_session(conn.assigns.current_user, id)
    back(conn, :security)
  end

  def delete_other_sessions(conn, _params) do
    Accounts.revoke_other_sessions(conn.assigns.current_user, conn.assigns.current_session)
    conn |> put_flash(:info, gettext("Other sessions closed.")) |> back(:security)
  end

  def update_preferences(conn, %{"preferences" => attrs}) do
    case Accounts.update_preferences(conn.assigns.current_user, attrs) do
      {:ok, user} ->
        conn
        |> put_flash(:info, gettext("Preferences saved."))
        |> redirect(to: Paths.account(user.locale, :security))

      {:error, _} ->
        back(conn, :security)
    end
  end

  def delete_account(conn, _params) do
    user = conn.assigns.current_user

    case Accounts.delete_account(user) do
      {:ok, _} ->
        conn |> configure_session(drop: true) |> redirect(to: Paths.home(user.locale))

      {:error, :last_admin} ->
        conn
        |> put_flash(:error, gettext("The last administrator cannot delete their account."))
        |> back(:security)
    end
  end

  @doc "For public pages: who is signed in, what they follow, the token to change it."
  def me(conn, _params) do
    conn = put_resp_header(conn, "cache-control", "private, no-store")

    case conn.assigns.current_user do
      nil ->
        json(conn, %{signed_in: false})

      user ->
        json(conn, %{
          signed_in: true,
          admin: user.role == "admin",
          account: Paths.account(user.locale),
          favorites: Accounts.favorite_keys(user),
          csrf: Plug.CSRFProtection.get_csrf_token()
        })
    end
  end

  defp back(conn, tab), do: redirect(conn, to: Paths.account(conn.assigns.locale, tab))

  # A favourite as the page shows it: its name and where it leads.
  defp describe(%Favorite{kind: "area", ref: code} = f, locale) do
    case Geo.get_area_by_code(code) do
      nil ->
        %{favorite: f, name: code, href: nil, area: nil}

      area ->
        %{
          favorite: f,
          name: Geo.Area.name(area, locale),
          href: Paths.area(locale, area),
          area: area
        }
    end
  end

  defp describe(%Favorite{kind: "exchange", ref: code} = f, locale),
    do: %{favorite: f, name: code, href: Paths.exchange(locale, code), area: nil}

  defp describe(%Favorite{kind: "security", ref: ref} = f, locale) do
    case String.split(ref, "/") do
      [exchange, ticker] ->
        %{favorite: f, name: ticker, href: Paths.security(locale, exchange, ticker), area: nil}

      _ ->
        %{favorite: f, name: ref, href: nil, area: nil}
    end
  end

  defp describe(%Favorite{kind: "comparison", ref: ref} = f, locale) do
    areas =
      ref |> String.split("/") |> Enum.map(&Geo.get_area_by_code/1) |> Enum.reject(&is_nil/1)

    %{
      favorite: f,
      name: Enum.map_join(areas, ", ", &Geo.Area.name(&1, locale)),
      href: Paths.compare(locale, Enum.map(areas, &Geo.Area.slug(&1, locale))),
      area: nil
    }
  end
end
