defmodule SyliAtlas.Fixtures do
  @moduledoc "Loads reference areas and the bundled IMF snapshot, sovereign ratings and national figures into the test database."

  def load_snapshot! do
    SyliAtlas.Geo.seed_areas!()
    SyliAtlas.Sources.seed_sources!()
    {:ok, :published, edition} = SyliAtlas.Imports.import_snapshot!()
    SyliAtlas.Ratings.seed!()
    SyliAtlas.National.seed!()
    edition
  end
end
