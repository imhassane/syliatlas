import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :syli_atlas, SyliAtlas.Repo,
  database: Path.expand("../syli_atlas_test.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :syli_atlas, SyliAtlasWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "viST6WNi2fbHHsVR4ZGQLCOKsouYGOy/ZslUqnG1OHIJkaUPmFtIgbmIy5yWDw8w",
  server: false

# In test we don't send emails
config :syli_atlas, SyliAtlas.Mailer, adapter: Swoosh.Adapters.Test

config :syli_atlas, SyliAtlas.Accounts.Passkeys,
  origin: "https://syliatlas.test",
  rp_id: "syliatlas.test"

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Run Oban jobs inline during tests, without cron or queues.
config :syli_atlas, Oban, testing: :manual

# Market data: raw payloads on disk, the Mansa API stubbed (Req.Test).
config :syli_atlas, SyliAtlas.Market.RawStore,
  adapter: SyliAtlas.Market.RawStore.Local,
  root: Path.expand("../tmp/test_raw", __DIR__)

config :syli_atlas, SyliAtlas.Market.Sources.Mansa,
  api_key: "test-key",
  req_options: [plug: {Req.Test, SyliAtlas.Market.Sources.Mansa}, retry: false]

# Tests call the API far more than 60 times a minute from one address;
# the limiter's own tests lower the limit for themselves.
config :syli_atlas, SyliAtlasWeb.Plugs.ApiRateLimit, public: 100_000, internal: 100_000

# Cloudflare purge, stubbed (Req.Test); zone and token set by the tests that need them.
config :syli_atlas, SyliAtlas.Cdn, req_options: [plug: {Req.Test, SyliAtlas.Cdn}, retry: false]

# Admin credentials and the ratings watch, stubbed (Req.Test).

config :syli_atlas, SyliAtlas.Ratings.Extractor,
  api_key: "test-key",
  req_options: [plug: {Req.Test, SyliAtlas.Ratings.Extractor}, retry: false]

config :syli_atlas, SyliAtlas.Ratings.Watch,
  feeds: [{"test", "https://feeds.test/ratings.xml"}],
  req_options: [plug: {Req.Test, SyliAtlas.Ratings.Watch}, retry: false]

# Exchange rates: both sources stubbed (Req.Test).
config :syli_atlas, SyliAtlas.Fx.Sources.ExchangeApi,
  req_options: [plug: {Req.Test, SyliAtlas.Fx.Sources.ExchangeApi}, retry: false]

config :syli_atlas, SyliAtlas.Fx.Sources.ErApi,
  req_options: [plug: {Req.Test, SyliAtlas.Fx.Sources.ErApi}, retry: false]
