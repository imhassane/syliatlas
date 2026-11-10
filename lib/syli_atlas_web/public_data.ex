defmodule SyliAtlasWeb.PublicData do
  @moduledoc "Loads and decodes JSON function answers for HTML pages."
  alias SyliAtlas.Profiles.Queries

  def area(code, from, to) do
    case Queries.area_profile(code, from, to) do
      nil -> nil
      json -> Jason.decode!(json)
    end
  end

  def compare(codes, from, to), do: codes |> Queries.compare(from, to) |> decode_list()

  def ranking(indicator, from, to, opts),
    do: indicator |> Queries.ranking(from, to, opts) |> decode_list()

  @doc "The home map snapshot: %{\"from\", \"to\", \"countries\"} or nil before the first import."
  def map(locale) do
    case Queries.map_countries(locale) do
      nil -> nil
      json -> Jason.decode!(json)
    end
  end

  @doc "The home page snapshot, or nil before the first import."
  def home(locale) do
    case Queries.home(locale) do
      nil -> nil
      json -> Jason.decode!(json)
    end
  end

  @doc """
  The regions page data for a period: the stored snapshot for the default
  period, computed live by the same builder for any other.
  """
  def regions(locale, from, to) do
    with true <- {from, to} == SyliAtlas.Profiles.Builder.default_period(),
         json when is_binary(json) <- Queries.regions(locale) do
      Jason.decode!(json)
    else
      _ -> SyliAtlas.Profiles.RegionsSnapshot.build(locale, from, to)
    end
  end

  def search(q, locale), do: q |> Queries.search(locale) |> decode_list()

  def at(values, year) when is_list(values), do: Enum.at(values, year - 2015)
  def at(_values, _year), do: nil

  defp decode_list(nil), do: []
  defp decode_list(json), do: Jason.decode!(json)
end
