import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/syli_atlas start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :syli_atlas, SyliAtlasWeb.Endpoint, server: true
end

config :syli_atlas, SyliAtlasWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

# Content-Security-Policy of HTML pages (SyliAtlasWeb.CSP): "report-only" (default:
# violations are reported to /csp-report, nothing is blocked), "enforce" (the
# browser blocks them) or "off" (only Phoenix's base-uri/frame-ancestors).
csp_mode =
  case System.get_env("CSP_MODE", "report-only") do
    "enforce" -> :enforce
    "off" -> :off
    "report-only" -> :report_only
    other -> raise "CSP_MODE must be report-only, enforce or off, got: #{inspect(other)}"
  end

config :syli_atlas, SyliAtlasWeb.CSP, mode: csp_mode

# Market data. The Mansa key is the Railway variable STOCK_EXCHANGE_API_KEY
# (the lower-case spelling is accepted too: environment variable names are
# case-sensitive). Without it, the market import cancels itself and the
# pages show "figures on their way".
if config_env() != :test do
  config :syli_atlas, SyliAtlas.Market.Sources.Mansa,
    api_key:
      Enum.find_value(
        ["STOCK_EXCHANGE_API_KEY", "stock_exchange_api_key"],
        &(System.get_env(&1)
          |> then(fn v -> if v in [nil, ""], do: nil, else: String.trim(v) end))
      )
end

# MANSA_FAKE=true (development): the market import reads
# SyliAtlas.Market.Sources.MansaFake instead of mansaapi.com, fictitious
# figures that spend none of the shared daily quota. Refused in the Railway
# environment named "production".
if config_env() != :test and System.get_env("MANSA_FAKE") in ~w(true 1) do
  if System.get_env("RAILWAY_ENVIRONMENT_NAME") == "production",
    do: raise("MANSA_FAKE=true is refused in production: fictitious market figures")

  config :syli_atlas, SyliAtlas.Market.Sources.Mansa,
    req_options: [plug: SyliAtlas.Market.Sources.MansaFake, retry: false]

  config :syli_atlas, SyliAtlas.Market, fake: true
end

# Ratings watch: the AI extraction uses the Railway variable ANTHROPIC_API_KEY.
# Without it, the watch still collects the news but proposes nothing.
# (The administration needs an administrator account: the email code, then
# a passkey. ADMIN_USER and ADMIN_PASSWORD are no longer read.)
if config_env() != :test do
  config :syli_atlas, SyliAtlas.Ratings.Extractor,
    api_key:
      (case System.get_env("ANTHROPIC_API_KEY") do
         v when v in [nil, ""] -> nil
         v -> String.trim(v)
       end)
end

# Cloudflare: after each publication, the API answers are dropped from its
# cache (SyliAtlas.Cdn). CLOUDFLARE_ZONE_ID and CLOUDFLARE_API_TOKEN (a token
# with the single permission Zone > Cache Purge). Without them, no purge.
# RATE_LIMIT_PER_MINUTE changes the public API limit (60 by default).
if config_env() != :test do
  env = fn name ->
    case System.get_env(name) do
      v when v in [nil, ""] -> nil
      v -> String.trim(v)
    end
  end

  config :syli_atlas, SyliAtlas.Cdn,
    zone_id: env.("CLOUDFLARE_ZONE_ID"),
    api_token: env.("CLOUDFLARE_API_TOKEN")

  if limit = env.("RATE_LIMIT_PER_MINUTE") do
    config :syli_atlas, SyliAtlasWeb.Plugs.ApiRateLimit,
      enabled: true,
      public: String.to_integer(limit),
      internal: 240
  end
end

# Emails (sign-in codes, alerts, digests). MAILER_ADAPTER chooses, else
# the variables present do:
#
#   resend   RESEND_API_KEY                   production (Resend's HTTP API, SyliAtlas.Mailer.Resend)
#   smtp     SMTP_HOST, SMTP_PORT (1025)      Mailpit on Railway, or a local one
#            SMTP_USERNAME, SMTP_PASSWORD     only if the server asks (Mailpit: no)
#            SMTP_TLS never | if_available | always (default never: Mailpit
#            talks plain SMTP on the private network)
#   local    nothing                          /dev/mailbox, development only
#
# A release with none of them sends nothing: sign-in says it is not open
# yet (never a code written to the logs). MAIL_FROM: "Syli Atlas
# <bonjour@…>", an address of a domain verified at Resend in production.
# FIRST_ADMIN_EMAIL, when set, is the only address that can become the
# first administrator.
if config_env() != :test do
  env = fn name -> System.get_env(name) |> then(&if(&1 in [nil, ""], do: nil, else: &1)) end

  adapter =
    cond do
      adapter = env.("MAILER_ADAPTER") -> adapter
      env.("RESEND_API_KEY") -> "resend"
      env.("SMTP_HOST") -> "smtp"
      config_env() == :dev -> "local"
      true -> "none"
    end

  mailer =
    case adapter do
      "resend" ->
        # Our adapter (SyliAtlas.Mailer.Resend): Resend's HTTP API with Req,
        # headers as Resend expects them, idempotency keys.
        [
          adapter: SyliAtlas.Mailer.Resend,
          api_key: env.("RESEND_API_KEY") || raise("MAILER_ADAPTER=resend needs RESEND_API_KEY")
        ]

      "smtp" ->
        tls =
          case env.("SMTP_TLS") || "never" do
            "never" -> :never
            "if_available" -> :if_available
            "always" -> :always
            other -> raise "SMTP_TLS=#{other}: expected never, if_available or always"
          end

        credentials =
          case {env.("SMTP_USERNAME"), env.("SMTP_PASSWORD")} do
            {nil, _} -> [auth: :never]
            {user, password} -> [auth: :always, username: user, password: password || ""]
          end

        [
          adapter: Swoosh.Adapters.SMTP,
          relay: env.("SMTP_HOST") || "localhost",
          port: String.to_integer(env.("SMTP_PORT") || "1025"),
          ssl: false,
          tls: tls,
          retries: 1,
          no_mx_lookups: true
        ] ++ credentials

      "local" ->
        if config_env() == :prod,
          do:
            raise(
              "MAILER_ADAPTER=local keeps emails in memory, unreadable in a release: use smtp (Mailpit) or resend"
            )

        [adapter: Swoosh.Adapters.Local]

      "none" ->
        nil

      other ->
        raise "unknown MAILER_ADAPTER #{inspect(other)}, expected resend, smtp or local"
    end

  if mailer, do: config(:syli_atlas, SyliAtlas.Mailer, mailer)
  config :syli_atlas, :mail_enabled, mailer != nil

  # What the boot log and the admin show: the service, never a secret.
  service = if adapter == "smtp", do: "smtp #{mailer[:relay]}:#{mailer[:port]}", else: adapter
  config :syli_atlas, :mail_adapter, service

  case System.get_env("MAIL_FROM") do
    nil ->
      :ok

    from ->
      case Regex.run(~r/^\s*(.*?)\s*<([^>]+)>\s*$/, from) do
        [_, name, address] -> config :syli_atlas, :mail_from, {name, address}
        nil -> config :syli_atlas, :mail_from, {"Syli Atlas", String.trim(from)}
      end
  end

  case System.get_env("FIRST_ADMIN_EMAIL") do
    v when v in [nil, ""] -> :ok
    v -> config :syli_atlas, :first_admin_email, v |> String.trim() |> String.downcase()
  end
end

# Raw payloads go to Cloudflare R2 when its four variables are set, else to
# the disk next to the database (a Railway volume).
if r2_bucket = System.get_env("R2_BUCKET") do
  config :syli_atlas, SyliAtlas.Market.RawStore.R2,
    account_id: System.fetch_env!("R2_ACCOUNT_ID"),
    access_key_id: System.fetch_env!("R2_ACCESS_KEY_ID"),
    secret_access_key: System.fetch_env!("R2_SECRET_ACCESS_KEY"),
    bucket: r2_bucket

  config :syli_atlas, SyliAtlas.Market.RawStore, adapter: SyliAtlas.Market.RawStore.R2
end

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :syli_atlas, SyliAtlasWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$",
        # Gettext translations
        ~r"priv/gettext/.*\.po$",
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/syli_atlas_web/router\.ex$",
        ~r"lib/syli_atlas_web/(controllers|live|components)/.*\.(ex|heex)$"
      ]
    ]
end

if config_env() == :prod do
  database_path =
    System.get_env("DATABASE_PATH") ||
      raise """
      environment variable DATABASE_PATH is missing.
      For example: /etc/syli_atlas/syli_atlas.db
      """

  config :syli_atlas, SyliAtlas.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5")

  # Market pages: shown when an active source's licence allows public
  # display (MansaAPI's does); MARKET_PREVIEW=true forces them on otherwise.
  config :syli_atlas, SyliAtlas.Market, preview: System.get_env("MARKET_PREVIEW") == "true"

  # Share images, drawn once per version and kept on the volume; the main
  # ones are drawn again after each deploy.
  config :syli_atlas, SyliAtlasWeb.OgImageController,
    cache_dir: Path.join(Path.dirname(database_path), "og")

  config :syli_atlas, og_warm_on_boot: true
  # First deploy of the exchange rates: import at once rather than at 01:10 UTC.
  config :syli_atlas, fx_import_on_boot: true
  # Past closes of the main indices for the simulator, once (7 Mansa calls).
  config :syli_atlas, index_history_on_boot: true

  unless System.get_env("R2_BUCKET") do
    config :syli_atlas, SyliAtlas.Market.RawStore,
      adapter: SyliAtlas.Market.RawStore.Local,
      root: Path.join(Path.dirname(database_path), "raw")
  end

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  # Search engines and the public address (SyliAtlasWeb.Plugs.CanonicalHost).
  # Other hosts are redirected to PHX_HOST, unless PHX_HOST is itself the
  # Railway address (the site would then redirect its own domain away).
  # SITE_NOINDEX=true keeps an environment (development) out of search engines.
  config :syli_atlas, :site,
    canonical_redirect:
      System.get_env("CANONICAL_REDIRECT", "true") == "true" and
        not String.ends_with?(host, ".up.railway.app") and host != "example.com",
    noindex: System.get_env("SITE_NOINDEX") == "true",
    # Shown on the accessibility statement: where to report a barrier.
    contact_email: System.get_env("CONTACT_EMAIL")

  # Passkeys belong to the site's host: changing PHX_HOST makes existing ones unusable.
  config :syli_atlas, SyliAtlas.Accounts.Passkeys,
    origin: "https://" <> host,
    rp_id: host

  config :syli_atlas, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :syli_atlas, SyliAtlasWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      # PHX_IPV4=true binds IPv4 only, for hosts without IPv6.
      ip:
        if(System.get_env("PHX_IPV4") == "true", do: {0, 0, 0, 0}, else: {0, 0, 0, 0, 0, 0, 0, 0})
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :syli_atlas, SyliAtlasWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :syli_atlas, SyliAtlasWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :syli_atlas, SyliAtlas.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://swoosh.hexdocs.pm/Swoosh.html#module-installation for details.
end
