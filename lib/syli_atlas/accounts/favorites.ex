defmodule SyliAtlas.Accounts.Favorites do
  @moduledoc "What a member follows, shown in their space and marked on public pages."
  import Ecto.Query

  alias SyliAtlas.Accounts.{Favorite, User}
  alias SyliAtlas.Repo

  @max_per_user 200

  def list(%User{id: id}),
    do: Favorite |> where(user_id: ^id) |> order_by(desc: :inserted_at) |> Repo.all()

  @doc "Adds a favourite; adding it twice is not an error."
  def add(%User{id: id}, kind, ref) do
    if Repo.aggregate(where(Favorite, user_id: ^id), :count) >= @max_per_user do
      {:error, :too_many_favorites}
    else
      case id |> Favorite.changeset(kind, ref) |> Repo.insert(on_conflict: :nothing) do
        {:ok, _favorite} -> :ok
        {:error, _changeset} -> {:error, :invalid_favorite}
      end
    end
  end

  def remove(%User{id: id}, kind, ref) do
    Repo.delete_all(
      from f in Favorite, where: f.user_id == ^id and f.kind == ^kind and f.ref == ^ref
    )

    :ok
  end

  @doc "The favourites as `\"kind:ref\"` strings, for the stars of public pages."
  def keys(%User{} = user), do: user |> list() |> Enum.map(&"#{&1.kind}:#{&1.ref}")
end
