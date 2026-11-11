defmodule SyliAtlas.Accounts.Emails do
  @moduledoc """
  The account emails (sign-in code, welcome, first administrator, security
  notices), in the recipient's language, as plain text plus HTML
  (`SyliAtlas.Accounts.EmailLayout`). Sent with `deliver/1`.
  """

  use Gettext, backend: SyliAtlasWeb.Gettext
  require Logger

  alias SyliAtlas.Accounts.{EmailLayout, Passkey, User}
  alias SyliAtlasWeb.Paths

  @doc "Sends an email; `{:error, reason}` when the mailer refuses it."
  def deliver(%Swoosh.Email{} = email) do
    if configured?() do
      case SyliAtlas.Mailer.deliver(email) do
        {:ok, _meta} ->
          :ok

        {:error, reason} ->
          Logger.error("email not sent: #{inspect(reason)}")
          {:error, :not_sent}
      end
    else
      {:error, :mail_not_configured}
    end
  end

  @doc "Whether an email adapter is configured (see config/runtime.exs)."
  def configured?, do: Application.get_env(:syli_atlas, :mail_enabled, true)

  @doc "The sign-in code. Administrators are told their passkey comes next."
  def code(email, code, locale, admin?) do
    in_locale(locale, fn ->
      spaced = String.slice(code, 0, 3) <> " " <> String.slice(code, 3, 3)

      blocks =
        [
          {:paragraph,
           dgettext(
             "emails",
             "Enter this code on the Syli Atlas sign-in page. It is valid for 10 minutes and works once."
           )},
          {:code, spaced, dgettext("emails", "Valid for 10 minutes")}
        ] ++
          if admin? do
            [
              {:note,
               dgettext(
                 "emails",
                 "Administrator account: after this code, Syli Atlas will ask for your passkey (fingerprint, face or device PIN). Without it, the administration stays closed."
               )}
            ]
          else
            []
          end ++
          [
            {:paragraph,
             dgettext(
               "emails",
               "Did not ask for it? Ignore this email: nobody can sign in without this code."
             )}
          ]

      build(email, locale,
        subject: dgettext("emails", "%{code} is your Syli Atlas code", code: spaced),
        preheader: dgettext("emails", "Valid for 10 minutes, it works once."),
        eyebrow:
          if(admin?,
            do: dgettext("emails", "Sign-in · administration"),
            else: dgettext("emails", "Sign-in")
          ),
        title: dgettext("emails", "Your sign-in code"),
        blocks: blocks
      )
    end)
  end

  @doc "First sign-in of a member."
  def welcome(%User{} = user) do
    in_locale(user.locale, fn ->
      build(user.email, user.locale,
        subject: dgettext("emails", "Welcome to Syli Atlas"),
        preheader: dgettext("emails", "Your favourites and alerts are waiting in your space."),
        eyebrow: dgettext("emails", "Welcome"),
        title: dgettext("emails", "Your space is ready"),
        blocks: [
          {:paragraph,
           dgettext(
             "emails",
             "You can now follow the countries, exchanges and securities you care about, and be told when something changes."
           )},
          {:facts,
           [
             {dgettext("emails", "Favourites"),
              dgettext("emails", "the star at the top of each page")},
             {dgettext("emails", "Alerts"),
              dgettext("emails", "a threshold, a new rating, a new IMF edition")},
             {dgettext("emails", "Passkey"),
              dgettext("emails", "sign in with your fingerprint or face")}
           ]}
        ],
        button: {dgettext("emails", "Open my space"), url(Paths.account(user.locale))}
      )
    end)
  end

  @doc "The first account, which became the administrator."
  def first_admin(%User{} = user) do
    in_locale(user.locale, fn ->
      build(user.email, user.locale,
        subject: dgettext("emails", "You are the administrator of Syli Atlas"),
        preheader: dgettext("emails", "One last step: register your passkey."),
        eyebrow: dgettext("emails", "Administration"),
        title: dgettext("emails", "You are the administrator"),
        blocks: [
          {:paragraph,
           dgettext(
             "emails",
             "Your account is the first one created on Syli Atlas: it is the administrator. The following accounts will be members."
           )},
          {:paragraph,
           dgettext(
             "emails",
             "To protect the administration, every admin sign-in asks for two proofs: the code received by email, then your passkey (fingerprint, face or device PIN). Register it now, from the device you will use."
           )},
          {:paragraph,
           dgettext(
             "emails",
             "Tip: register a second passkey on another device, so you are never locked out."
           )}
        ],
        button: {dgettext("emails", "Register my passkey"), url(Paths.admin_key(user.locale))}
      )
    end)
  end

  @doc "A passkey was added to the account."
  def passkey_added(%User{} = user, %Passkey{} = passkey, device) do
    in_locale(user.locale, fn ->
      build(user.email, user.locale,
        subject: dgettext("emails", "A passkey was added to your account"),
        preheader: device,
        eyebrow: dgettext("emails", "Security"),
        title: dgettext("emails", "New passkey added"),
        blocks: [
          {:paragraph,
           dgettext(
             "emails",
             "A passkey was just registered on your account. It signs in without a code."
           )},
          {:facts,
           [
             {dgettext("emails", "Name"), passkey.name},
             {dgettext("emails", "Device"), device}
           ]},
          {:note,
           dgettext(
             "emails",
             "Not you? Remove this passkey now from « Security »: every session opened with it will be closed."
           )}
        ],
        button:
          {dgettext("emails", "Check my passkeys"), url(Paths.account(user.locale, :security))}
      )
    end)
  end

  @doc "A session reached the administration (code and passkey)."
  def admin_signed_in(%User{} = user, passkey_name, device) do
    in_locale(user.locale, fn ->
      build(user.email, user.locale,
        subject: dgettext("emails", "Sign-in to the Syli Atlas administration"),
        preheader: device,
        eyebrow: dgettext("emails", "Security · administration"),
        title: dgettext("emails", "New sign-in to the administration"),
        blocks: [
          {:paragraph, dgettext("emails", "Your administrator account just opened a session.")},
          {:facts,
           [
             {dgettext("emails", "Email code"), dgettext("emails", "verified")},
             {dgettext("emails", "Passkey"), passkey_name},
             {dgettext("emails", "Browser"), device}
           ]},
          {:note,
           dgettext(
             "emails",
             "Not you? Close every session and remove the passkey from « Security »."
           )}
        ],
        button:
          {dgettext("emails", "See open sessions"), url(Paths.account(user.locale, :security))}
      )
    end)
  end

  defp build(to, locale, opts), do: compose(to, locale, opts)

  @doc """
  An email in the layout: `:subject`, `:preheader`, `:eyebrow`, `:title`,
  `:blocks`, `:button`, `:footer` links, and `:unsubscribe` (a one-click
  URL, sent as the List-Unsubscribe headers of RFC 8058).
  """
  def compose(to, locale, opts) do
    opts = Keyword.put(opts, :language, locale)

    email =
      Swoosh.Email.new()
      |> Swoosh.Email.to(to)
      |> Swoosh.Email.from(from())
      |> Swoosh.Email.subject(Keyword.fetch!(opts, :subject))
      |> Swoosh.Email.text_body(EmailLayout.text(opts))
      |> Swoosh.Email.html_body(EmailLayout.render(opts))

    case opts[:unsubscribe] do
      nil ->
        email

      url ->
        email
        |> Swoosh.Email.header("List-Unsubscribe", "<#{url}>")
        |> Swoosh.Email.header("List-Unsubscribe-Post", "List-Unsubscribe=One-Click")
    end
  end

  defp from do
    case Application.get_env(:syli_atlas, :mail_from) do
      {name, address} -> {name, address}
      nil -> {"Syli Atlas", "noreply@" <> SyliAtlasWeb.Endpoint.host()}
    end
  end

  defp url(path), do: SyliAtlasWeb.Endpoint.url() <> path

  defp in_locale(locale, fun), do: Gettext.with_locale(SyliAtlasWeb.Gettext, locale, fun)
end
