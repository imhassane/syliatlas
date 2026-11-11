defmodule SyliAtlasWeb.Router do
  use SyliAtlasWeb, :router

  import SyliAtlasWeb.Auth, only: [fetch_current_user: 2, require_user: 2, put_account_locale: 2]

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SyliAtlasWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json", "csv"]
    plug SyliAtlasWeb.Plugs.ApiRateLimit
    plug SyliAtlasWeb.Plugs.ApiTiming
  end

  pipeline :public_cache do
    plug SyliAtlasWeb.Plugs.PublicCache
  end

  # Public pages: no session or CSRF token, so they can be cached.
  pipeline :public do
    plug :accepts, ["html"]
    plug :put_root_layout, html: {SyliAtlasWeb.Layouts, :root}
    plug :put_secure_browser_headers
  end

  # Sign-in and the member's space: the session, the signed-in account.
  pipeline :account do
    plug :fetch_current_user
    plug :put_account_locale
  end

  # Actions of the space and the passkey ceremonies: forms and JSON.
  pipeline :account_actions do
    plug :accepts, ["html", "json"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
    plug :put_account_locale
  end

  # Unsubscribe links of emails: the signed token is the proof, so mail
  # clients' one-click POST (RFC 8058) works without a session or CSRF token.
  pipeline :unsubscribe do
    plug :accepts, ["html"]
    plug :put_root_layout, html: {SyliAtlasWeb.Layouts, :root}
    plug :put_secure_browser_headers
  end

  # The country recap without an account (docs/recap.md). No session: the
  # form sits in the footer of cached pages, which carry no CSRF token. A
  # forged request can only make Syli Atlas send a confirmation email, which
  # the rate limits of SyliAtlas.Recaps bound; the other links carry a
  # signed token.
  pipeline :recap do
    plug :accepts, ["html", "json"]
    plug :put_root_layout, html: {SyliAtlasWeb.Layouts, :root}
    plug :put_secure_browser_headers
  end

  pipeline :admin do
    plug SyliAtlasWeb.Plugs.AdminAuth
    plug SyliAtlasWeb.Plugs.AdminShell
    plug :put_layout, false
    plug :admin_locale
  end

  defp admin_locale(conn, _opts) do
    Gettext.put_locale(SyliAtlasWeb.Gettext, "fr")
    assign(conn, :locale, "fr")
  end

  pipeline :fr do
    plug SyliAtlasWeb.Plugs.Locale, "fr"
  end

  pipeline :en do
    plug SyliAtlasWeb.Plugs.Locale, "en"
  end

  # Public pages: the language is the first segment of the path.
  pipeline :page_locale do
    plug SyliAtlasWeb.Plugs.Locale, :from_path
  end

  scope "/", SyliAtlasWeb do
    get "/health", HealthController, :show
    get "/sitemap.xml", SitemapController, :sitemap
    get "/sitemaps/:part", SitemapController, :part
    get "/robots.txt", SitemapController, :robots
    get "/llms.txt", SitemapController, :llms
    get "/llms-full.txt", SitemapController, :llms_full
    get "/og/:version/*path", OgImageController, :show
  end

  scope "/", SyliAtlasWeb do
    pipe_through :public
    get "/", PageController, :root
  end

  scope "/fr", SyliAtlasWeb do
    pipe_through [:browser, :fr, :account]

    get "/connexion", SessionController, :new
    post "/connexion", SessionController, :create
    get "/connexion/code", SessionController, :code
    post "/connexion/code", SessionController, :verify
    get "/connexion/cle", SessionController, :admin_key

    pipe_through :require_user
    get "/mon-espace", AccountController, :favorites
    get "/mon-espace/alertes", AccountController, :alerts
    get "/mon-espace/securite", AccountController, :security
  end

  scope "/en", SyliAtlasWeb do
    pipe_through [:browser, :en, :account]

    get "/sign-in", SessionController, :new
    post "/sign-in", SessionController, :create
    get "/sign-in/code", SessionController, :code
    post "/sign-in/code", SessionController, :verify
    get "/sign-in/passkey", SessionController, :admin_key

    pipe_through :require_user
    get "/my-space", AccountController, :favorites
    get "/my-space/alerts", AccountController, :alerts
    get "/my-space/security", AccountController, :security
  end

  scope "/fr", SyliAtlasWeb do
    pipe_through [:recap, :fr]
    get "/recap", RecapController, :new
    post "/recap", RecapController, :create
  end

  scope "/en", SyliAtlasWeb do
    pipe_through [:recap, :en]
    get "/recap", RecapController, :new
    post "/recap", RecapController, :create
  end

  scope "/recap", SyliAtlasWeb do
    pipe_through :recap

    get "/confirm/:token", RecapController, :confirmation
    post "/confirm/:token", RecapController, :confirm
    get "/manage/:token", RecapController, :manage
    post "/manage/:token", RecapController, :update
    get "/stop/:token", RecapController, :stop
    post "/stop/:token", RecapController, :unsubscribe
  end

  scope "/unsubscribe", SyliAtlasWeb do
    pipe_through :unsubscribe

    get "/:token", UnsubscribeController, :show
    post "/:token", UnsubscribeController, :create
  end

  scope "/account", SyliAtlasWeb do
    pipe_through :account_actions

    get "/me", AccountController, :me
    post "/passkey/options", PasskeyController, :sign_in_options
    post "/passkey", PasskeyController, :sign_in
    post "/passkeys/options", PasskeyController, :registration_options
    post "/passkeys", PasskeyController, :register
    post "/admin-proof/options", PasskeyController, :admin_options
    post "/admin-proof", PasskeyController, :admin_confirm

    pipe_through :require_user
    delete "/session", SessionController, :delete
    post "/favorites", AccountController, :toggle_favorite
    post "/alerts", AccountController, :create_alert
    put "/alerts/:id", AccountController, :update_alert
    delete "/alerts/:id", AccountController, :delete_alert
    delete "/passkeys/:id", AccountController, :delete_passkey
    delete "/sessions/:id", AccountController, :delete_session
    delete "/sessions", AccountController, :delete_other_sessions
    put "/preferences", AccountController, :update_preferences
    delete "/", AccountController, :delete_account
  end

  # The public pages, in every language of the site (SyliAtlas.Locales);
  # path segments from SyliAtlasWeb.Paths, so /fr/pays, /es/paises,
  # /ar/countries.
  for locale <- SyliAtlas.Locales.all() do
    seg = &SyliAtlasWeb.Paths.segment(locale, &1)

    # The API page shows hourly measures: its own cache headers (ApiDocController).
    scope "/#{locale}", SyliAtlasWeb do
      pipe_through [:public, :page_locale]
      get "/api", ApiDocController, :show
    end

    scope "/#{locale}", SyliAtlasWeb do
      pipe_through [:public, :page_locale, :public_cache]

      get "/", PageController, :home
      get "/#{seg.(:method)}", PageController, :method
      get "/#{seg.(:about)}", PageController, :about
      get "/#{seg.(:glossary)}", GlossaryController, :index
      get "/#{seg.(:glossary)}/:slug", GlossaryController, :show
      get "/#{seg.(:questions)}", QuestionsController, :index
      get "/#{seg.(:questions)}/:slug", QuestionsController, :show
      get "/#{seg.(:accessibility)}", PageController, :accessibility
      get "/#{seg.(:offline)}", PageController, :offline
      get "/#{seg.(:ranking)}", RankingController, :index
      get "/#{seg.(:ranking)}/:topic", RankingController, :topic
      get "/#{seg.(:search)}", SearchController, :index
      get "/#{seg.(:country)}/:slug", AreaController, :show
      get "/#{seg.(:country)}/:slug/#{seg.(:questions)}", CountryQuestionsController, :show
      get "/#{seg.(:country)}/:slug/:tab", AreaController, :show
      get "/#{seg.(:regions)}", RegionsController, :index
      get "/#{seg.(:regions)}/:slug", AreaController, :show
      get "/#{seg.(:compare)}", CompareController, :show
      get "/#{seg.(:compare)}/*slugs", CompareController, :show
      get "/#{seg.(:ratings)}", RatingsController, :index
      get "/#{seg.(:debt)}", DebtController, :index
      get "/#{seg.(:communities)}", CommunityController, :index
      get "/#{seg.(:communities)}/:slug", CommunityController, :show
      get "/#{seg.(:ratings)}/:slug", RatingsController, :show
      get "/#{seg.(:markets)}", MarketController, :index
      get "/#{seg.(:markets)}/etf", MarketController, :etfs
      get "/#{seg.(:markets)}/:exchange", MarketController, :exchange
      get "/#{seg.(:markets)}/:exchange/:ticker", MarketController, :security
    end
  end

  # Validation of the ratings (and, later, other data entered by hand).
  scope "/admin", SyliAtlasWeb.Admin do
    pipe_through [:browser, :admin]

    get "/", RatingsController, :root
    get "/notations", RatingsController, :index
    post "/notations", RatingsController, :create
    post "/notations/veille", RatingsController, :watch
    post "/notations/:id/approuver", RatingsController, :approve
    post "/notations/:id/rejeter", RatingsController, :reject
    post "/notations/verifier/:id", RatingsController, :check
    get "/mises-a-jour", UpdatesController, :index
    post "/mises-a-jour/verifier", UpdatesController, :check
    post "/mises-a-jour/mesurer", UpdatesController, :measure
    post "/mises-a-jour/files/:queue", UpdatesController, :pause
    post "/mises-a-jour/taches/:id/relancer", UpdatesController, :retry_job
    get "/mises-a-jour/editions/:id", UpdatesController, :edition
    post "/mises-a-jour/editions/:id/relancer", UpdatesController, :rerun
    post "/mises-a-jour/editions/:id/restaurer", UpdatesController, :restore
    get "/marches", MarketController, :index
    post "/marches/importer", MarketController, :import
    post "/marches/pause", MarketController, :pause
    post "/marches/anomalies/:id", MarketController, :decide
    get "/emails", EmailsController, :index
    post "/membres/:id/sessions", MembersController, :close_sessions
    get "/recherches", SearchMissesController, :index
    get "/membres", MembersController, :index
    post "/membres/:id/role", MembersController, :role
    post "/membres/:id/actif", MembersController, :active
  end

  # The public API, v1: described in /api/v1/openapi.json, documented at /fr/api.
  scope "/api/v1", SyliAtlasWeb.Api do
    pipe_through :api

    # Old addresses of the site's own calls, for service workers installed
    # before they moved to /api/internal. To remove after 15 December 2026.
    get "/version", InternalController, :version

    pipe_through :public_cache
    get "/search", InternalController, :search
    get "/offline-pack", InternalController, :offline_pack
    get "/offline-pages", InternalController, :offline_pages

    get "/", ApiController, :index
    get "/openapi.json", ApiController, :openapi
    get "/areas", ApiController, :areas
    get "/areas/:code", ApiController, :area
    get "/areas/:code/csv", ApiController, :csv
    get "/compare", ApiController, :compare
    get "/ranking", ApiController, :ranking
    get "/indicators", ApiController, :indicators
    get "/*path", ApiController, :not_found
  end

  # What the site itself calls: not part of the public API.
  scope "/api/internal", SyliAtlasWeb.Api do
    pipe_through :api

    get "/version", InternalController, :version

    pipe_through :public_cache
    get "/search", InternalController, :search
    get "/offline-pack", InternalController, :offline_pack
    get "/offline-pages", InternalController, :offline_pages
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:syli_atlas, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: SyliAtlasWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
