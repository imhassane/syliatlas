defmodule SyliAtlas.Social.Simulated do
  @moduledoc """
  Buffer's stand-in outside production: every post « succeeds » with a made-up
  id and nothing is sent. The admin marks those posts « simulé ».
  """
  @behaviour SyliAtlas.Social.Publisher

  require Logger

  @impl true
  def channels,
    do:
      {:ok,
       [
         %{id: "simulated-x", name: "syliatlas (simulé)", service: "twitter"},
         %{id: "simulated-linkedin", name: "syli-atlas (simulé)", service: "linkedin"}
       ]}

  @impl true
  def publish(network, %{text: text}, mode \\ :queue) do
    Logger.info("social: simulated #{network} post, #{mode} (#{String.length(text)} characters)")
    {:ok, "simulated-#{network}-#{System.unique_integer([:positive])}"}
  end

  # Nothing was sent, so nothing changes.
  @impl true
  def posts(_ids), do: {:ok, %{}}

  @impl true
  def delete(_id), do: :ok

  @impl true
  def schedule(_network), do: {:ok, SyliAtlas.Social.Publisher.default_schedule()}
end
