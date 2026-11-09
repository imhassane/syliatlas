defmodule SyliAtlas.Events do
  @moduledoc "PubSub topics shared by the admin and the background jobs."

  @topic "data_updates"

  def subscribe, do: Phoenix.PubSub.subscribe(SyliAtlas.PubSub, @topic)

  def broadcast_edition_published(edition),
    do: Phoenix.PubSub.broadcast(SyliAtlas.PubSub, @topic, {:edition_published, edition.id})
end
