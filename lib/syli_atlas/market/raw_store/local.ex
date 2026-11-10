defmodule SyliAtlas.Market.RawStore.Local do
  @moduledoc """
  Keeps raw payloads on the local disk, under `:root` (by default
  `priv/raw` of the application, or next to the database in production).
  """
  @behaviour SyliAtlas.Market.RawStore

  def root do
    Application.get_env(:syli_atlas, SyliAtlas.Market.RawStore, [])[:root] ||
      Path.join(System.tmp_dir!(), "syli_atlas_raw")
  end

  @impl true
  def put(key, body, _content_type) do
    path = Path.join(root(), key)

    with :ok <- File.mkdir_p(Path.dirname(path)) do
      File.write(path, body)
    end
  end

  @impl true
  def get(key), do: File.read(Path.join(root(), key))
end
