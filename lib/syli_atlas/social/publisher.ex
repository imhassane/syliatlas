defmodule SyliAtlas.Social.Publisher do
  @moduledoc """
  Where approved posts go. Chosen at boot (config/runtime.exs):
  `SyliAtlas.Social.Buffer` when `BUFFER_API_KEY` is set (production),
  else `SyliAtlas.Social.Simulated` (development, Railway's dev environment,
  tests): nothing leaves the server.
  """

  @type network :: :x | :linkedin
  @type post :: %{
          required(:text) => String.t(),
          optional(:image_url) => String.t() | nil
        }

  @doc "The connected accounts: `%{id, name, service}`."
  @callback channels() :: {:ok, [map()]} | {:error, String.t()}

  @doc "Adds one post to the network's queue; returns the service's id."
  @callback publish(network(), post()) :: {:ok, String.t()} | {:error, String.t()}

  def adapter,
    do:
      Application.get_env(:syli_atlas, SyliAtlas.Social, [])[:adapter] ||
        SyliAtlas.Social.Simulated

  def simulated?, do: adapter() == SyliAtlas.Social.Simulated
end
