defmodule SyliAtlas.Accounts.Unsubscribe do
  @moduledoc """
  Unsubscribe links of the emails: a signed token (no account needed, no
  table), valid 400 days. `:alert` pauses one alert, `:digest` stops the
  digest, `:all` both for every alert. The page asks before acting (mail
  scanners open links); mail clients' one-click POST acts at once.
  """
  import Ecto.Query

  alias SyliAtlas.Accounts.{Alert, User}
  alias SyliAtlas.Repo

  @salt "unsubscribe"
  @max_age 400 * 24 * 3600

  def token(scope, id) when scope in [:alert, :digest, :all],
    do: Phoenix.Token.sign(SyliAtlasWeb.Endpoint, @salt, [Atom.to_string(scope), id])

  def path(token), do: "/unsubscribe/" <> token

  @doc "What a token stops, and for whom: `{:ok, scope, user, alert | nil}` or `:error`."
  def resolve(token) do
    with {:ok, [scope, id]} <-
           Phoenix.Token.verify(SyliAtlasWeb.Endpoint, @salt, token, max_age: @max_age),
         {:ok, user, alert} <- load(scope, id) do
      {:ok, scope, user, alert}
    else
      _ -> :error
    end
  end

  defp load("alert", id) do
    case Repo.one(from a in Alert, where: a.id == ^id, preload: :user) do
      nil -> :error
      alert -> {:ok, alert.user, alert}
    end
  end

  defp load(scope, id) when scope in ["digest", "all"] do
    case Repo.get(User, id) do
      nil -> :error
      user -> {:ok, user, nil}
    end
  end

  defp load(_scope, _id), do: :error

  @doc "Applies a token. Idempotent."
  def apply(token) do
    case resolve(token) do
      {:ok, "alert", user, alert} ->
        Repo.update_all(where(Alert, id: ^alert.id), set: [active: false])
        {:ok, "alert", user}

      {:ok, "digest", user, nil} ->
        Repo.update_all(where(User, id: ^user.id), set: [digest: "never"])
        {:ok, "digest", user}

      {:ok, "all", user, nil} ->
        Repo.transaction(fn ->
          Repo.update_all(where(Alert, user_id: ^user.id), set: [active: false])
          Repo.update_all(where(User, id: ^user.id), set: [digest: "never"])
        end)

        {:ok, "all", user}

      :error ->
        :error
    end
  end
end
