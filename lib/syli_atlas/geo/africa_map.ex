defmodule SyliAtlas.Geo.AfricaMap do
  @moduledoc """
  SVG paths of African countries, keyed by ISO 3166-1 alpha-3 code, for a
  map `width` × `height` px. Built by `scripts/build_africa_map.py` from
  Natural Earth (public domain); read once, then kept in persistent_term.
  """

  @key {__MODULE__, :map}

  @doc "%{width, height, areas: %{code => %{d, cx, cy, small}}}"
  def get do
    case :persistent_term.get(@key, nil) do
      nil ->
        map = load()
        :persistent_term.put(@key, map)
        map

      map ->
        map
    end
  end

  defp load do
    data =
      Application.app_dir(:syli_atlas, "priv/data/africa_map.json")
      |> File.read!()
      |> Jason.decode!()

    %{
      width: data["width"],
      height: data["height"],
      areas:
        Map.new(data["areas"], fn {code, a} ->
          {code, %{d: a["d"], cx: a["cx"], cy: a["cy"], small: a["small"]}}
        end)
    }
  end
end
