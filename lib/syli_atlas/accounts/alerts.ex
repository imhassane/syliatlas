defmodule SyliAtlas.Accounts.Alerts do
  @moduledoc "A member's alerts: created, paused, changed and deleted from their space."
  import Ecto.Query

  alias SyliAtlas.Accounts.{Alert, AlertEvents, User}
  alias SyliAtlas.Repo

  def list(%User{id: id}),
    do: Alert |> where(user_id: ^id) |> order_by(desc: :inserted_at) |> Repo.all()

  def get(%User{id: user_id}, id) do
    case Integer.parse(to_string(id)) do
      {int, ""} -> Repo.get_by(Alert, id: int, user_id: user_id)
      _ -> nil
    end
  end

  def change(alert \\ %Alert{}, attrs \\ %{}), do: Alert.changeset(alert, attrs)

  def create(%User{id: user_id}, attrs) do
    if Repo.aggregate(where(Alert, user_id: ^user_id), :count) >= Alert.max_per_user() do
      {:error, :too_many_alerts}
    else
      %Alert{user_id: user_id} |> Alert.changeset(attrs) |> put_baseline() |> Repo.insert()
    end
  end

  # A threshold starts from today's published value: it fires when a later
  # edition crosses it from there (`SyliAtlas.Accounts.AlertRules`).
  defp put_baseline(%Ecto.Changeset{valid?: true} = changeset) do
    case Ecto.Changeset.apply_changes(changeset) do
      %Alert{kind: kind, area_code: area, indicator: indicator}
      when kind in ~w(indicator_above indicator_below) ->
        {value, year} = AlertEvents.baseline(area, indicator)
        Ecto.Changeset.change(changeset, last_value: value, last_year: year)

      _other ->
        changeset
    end
  end

  defp put_baseline(changeset), do: changeset

  def update(%Alert{} = alert, attrs), do: alert |> Alert.changeset(attrs) |> Repo.update()

  def delete(%User{} = user, id) do
    case get(user, id) do
      nil -> {:error, :not_found}
      alert -> Repo.delete(alert)
    end
  end

  @doc "Counts per area code, for the badges of the favourites."
  def counts_by_area(%User{id: id}) do
    Repo.all(
      from a in Alert,
        where: a.user_id == ^id and a.active,
        group_by: a.area_code,
        select: {a.area_code, count(a.id)}
    )
    |> Map.new()
  end
end
