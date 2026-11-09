# Seeds reference data and imports the bundled IMF snapshot.
#
#     mix run priv/repo/seeds.exs
SyliAtlas.Geo.seed_areas!()
SyliAtlas.Sources.seed_sources!()
{:ok, _status, edition} = SyliAtlas.Imports.import_snapshot!()
IO.puts("IMF edition #{edition.code} online")
