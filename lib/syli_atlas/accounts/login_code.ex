defmodule SyliAtlas.Accounts.LoginCode do
  @moduledoc """
  A one-time code sent by email: valid 10 minutes, 5 attempts, used once.
  Only HMACs are stored (`SyliAtlas.Accounts.Secrets`).
  """
  use Ecto.Schema

  @ttl_seconds 10 * 60
  @max_attempts 5
  @max_per_hour 5

  schema "login_codes" do
    field :email_hash, :binary
    field :code_hash, :binary
    field :attempts, :integer, default: 0
    field :expires_at, :utc_datetime
    field :consumed_at, :utc_datetime

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def ttl_seconds, do: @ttl_seconds
  def max_attempts, do: @max_attempts
  def max_per_hour, do: @max_per_hour

  @doc "Whether a code may still be tried."
  def check(%__MODULE__{} = code, now) do
    cond do
      code.consumed_at != nil -> {:error, :already_used}
      code.attempts >= @max_attempts -> {:error, :too_many_attempts}
      DateTime.compare(now, code.expires_at) != :lt -> {:error, :expired}
      true -> :ok
    end
  end
end
