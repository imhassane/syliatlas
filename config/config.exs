# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :syli_atlas,
  ecto_repos: [SyliAtlas.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :syli_atlas, SyliAtlasWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: SyliAtlasWeb.ErrorHTML, json: SyliAtlasWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: SyliAtlas.PubSub,
  live_view: [signing_salt: "F1iT2f0k"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Background jobs. Oban runs on the same SQLite database with the Lite engine.
config :syli_atlas, Oban,
  engine: Oban.Engines.Lite,
  repo: SyliAtlas.Repo,
  queues: [imports: 1, computations: 2, seo: 1, alerts: 2, moderation: 1, market: 1],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 30},
    {Oban.Plugins.Cron,
     crontab: [
       # Ask every source for a new edition each morning (UTC).
       {"0 6 * * *", SyliAtlas.Workers.CheckSourcesWorker},
       # Market closes, once every African exchange has closed (UTC, weekdays).
       # Mansa refreshes most exchanges at 16:30 UTC and the VFEX at 20:00:
       # a full import after the first, a catch-up of what is still behind
       # after the second (see MarketImportWorker).
       {"45 16 * * 1-5", SyliAtlas.Workers.MarketImportWorker},
       {"15 20 * * 1-5", SyliAtlas.Workers.MarketImportWorker, args: %{"mode" => "catchup"}},
       # Ratings news watch: proposals for /admin/notations (agencies often
       # publish on Friday evenings, so the Saturday run catches them).
       {"20 7 * * *", SyliAtlas.Workers.RatingsWatchWorker}
     ]}
  ]

# Market pages are shown when an active source's licence allows public
# display, or in preview (dev and test; MARKET_PREVIEW=true in production).
config :syli_atlas, SyliAtlas.Market, preview: true

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :syli_atlas, SyliAtlas.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  syli_atlas: [
    args:
      ~w(js/app.js js/live.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
