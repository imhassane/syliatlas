defmodule SyliAtlasWeb.Router do
  use SyliAtlasWeb, :router

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

  pipeline :fr do
    plug SyliAtlasWeb.Plugs.Locale, "fr"
  end

  pipeline :en do
    plug SyliAtlasWeb.Plugs.Locale, "en"
  end

  scope "/", SyliAtlasWeb do
    get "/health", HealthController, :show
  end

  scope "/", SyliAtlasWeb do
    pipe_through :public
    get "/", PageController, :root
  end

  scope "/fr", SyliAtlasWeb do
    pipe_through [:public, :fr, :public_cache]

    get "/", PageController, :home
    get "/methode", PageController, :method
    get "/hors-ligne", PageController, :offline
    get "/classement", RankingController, :index
    get "/recherche", SearchController, :index
    get "/pays/:slug", AreaController, :show
    get "/regions", RegionsController, :index
    get "/regions/:slug", AreaController, :show
    get "/comparer", CompareController, :show
    get "/comparer/*slugs", CompareController, :show
  end

  scope "/en", SyliAtlasWeb do
    pipe_through [:public, :en, :public_cache]

    get "/", PageController, :home
    get "/method", PageController, :method
    get "/offline", PageController, :offline
    get "/ranking", RankingController, :index
    get "/search", SearchController, :index
    get "/countries/:slug", AreaController, :show
    get "/regions", RegionsController, :index
    get "/regions/:slug", AreaController, :show
    get "/compare", CompareController, :show
    get "/compare/*slugs", CompareController, :show
  end

  scope "/api/v1", SyliAtlasWeb.Api do
    pipe_through :api

    get "/version", ApiController, :version

    pipe_through :public_cache
    get "/areas", ApiController, :areas
    get "/areas/:code", ApiController, :area
    get "/areas/:code/csv", ApiController, :csv
    get "/compare", ApiController, :compare
    get "/ranking", ApiController, :ranking
    get "/search", ApiController, :search
    get "/offline-pack", ApiController, :offline_pack
    get "/offline-pages", ApiController, :offline_pages
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
