defmodule SyliAtlas.Repo do
  use Ecto.Repo,
    otp_app: :syli_atlas,
    adapter: Ecto.Adapters.SQLite3
end
