defmodule SyliAtlas.Search.Miss do
  @moduledoc """
  A search that found nothing. Only the normalised query and the language
  are kept, counted: no IP, no session, nothing that identifies a reader.
  """
  use Ecto.Schema
  import Ecto.Query

  alias SyliAtlas.Repo

  schema "search_misses" do
    field :query, :string
    field :locale, :string
    field :count, :integer, default: 1
    field :last_seen_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  @doc "Counts one more miss for this query (ignored if too short or too long)."
  def record(query, locale) when is_binary(query) do
    q = String.trim(query)

    if String.length(q) in 2..80 do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Repo.insert(
        %__MODULE__{query: q, locale: locale, count: 1, last_seen_at: now},
        on_conflict: [inc: [count: 1], set: [last_seen_at: now, updated_at: now]],
        conflict_target: [:query, :locale]
      )
    end

    :ok
  rescue
    _ -> :ok
  end

  def record(_query, _locale), do: :ok

  @doc "The most frequent misses first."
  def top(limit \\ 100) do
    Repo.all(from m in __MODULE__, order_by: [desc: m.count, desc: m.last_seen_at], limit: ^limit)
  end
end
