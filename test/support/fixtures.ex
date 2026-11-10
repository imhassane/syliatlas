defmodule SyliAtlas.Fixtures do
  @moduledoc "Loads reference areas and the bundled IMF snapshot and sovereign ratings into the test database."

  def load_snapshot! do
    SyliAtlas.Geo.seed_areas!()
    SyliAtlas.Sources.seed_sources!()
    {:ok, :published, edition} = SyliAtlas.Imports.import_snapshot!()
    SyliAtlas.Ratings.seed!()
    edition
  end
end
