defmodule SyliAtlasWeb.Api.Params do
  @moduledoc "Parses the period and filter parameters shared by pages and the API."
  alias SyliAtlas.Profiles.Builder

  @doc "Returns {:ok, from, to} or {:error, message}. Defaults to 2020 → 2025."
  def period(params) do
    {default_from, default_to} = Builder.default_period()

    with {:ok, from} <- year(params["from"], default_from),
         {:ok, to} <- year(params["to"], default_to) do
      if from < to, do: {:ok, from, to}, else: {:error, "from must be before to"}
    end
  end

  defp year(nil, default), do: {:ok, default}
  defp year("", default), do: {:ok, default}

  defp year(value, _default) do
    case Integer.parse(to_string(value)) do
      {y, ""} when y in 2015..2030 -> {:ok, y}
      _ -> {:error, "years must be between 2015 and 2030"}
    end
  end

  def locale(%{"locale" => locale}) when is_binary(locale) do
    if SyliAtlas.Locales.valid?(locale), do: locale, else: "fr"
  end

  def locale(_), do: "fr"

  def codes(nil), do: []

  def codes(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&Regex.match?(~r/^[A-Za-z_]{2,20}$/, &1))
    |> Enum.uniq()
    |> Enum.take(6)
  end
end
