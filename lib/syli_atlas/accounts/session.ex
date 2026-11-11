defmodule SyliAtlas.Accounts.Session do
  @moduledoc """
  A signed-in browser. It records when each proof was given: the
  administration needs both the email code and a passkey, given in this
  session within `admin_ttl_seconds/0`.
  """
  use Ecto.Schema

  # A member stays signed in 90 days (renewed on use); admin rights last 8 hours.
  @ttl_seconds 90 * 24 * 3600
  @admin_ttl_seconds 8 * 3600
  # A passkey can be enrolled without another passkey only right after a code.
  @fresh_code_seconds 10 * 60
  # The last use is written at most once an hour.
  @touch_seconds 3600

  schema "user_sessions" do
    belongs_to :user, SyliAtlas.Accounts.User
    belongs_to :passkey, SyliAtlas.Accounts.Passkey
    field :token_hash, :binary
    field :code_verified_at, :utc_datetime
    field :passkey_verified_at, :utc_datetime
    field :user_agent, :string, default: ""
    field :expires_at, :utc_datetime
    field :last_used_at, :utc_datetime
    field :revoked_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def ttl_seconds, do: @ttl_seconds
  def admin_ttl_seconds, do: @admin_ttl_seconds
  def touch_seconds, do: @touch_seconds

  @doc "Whether this session holds both proofs, recently enough for the administration."
  def admin_verified?(%__MODULE__{} = s, now) do
    recent?(s.code_verified_at, now, @admin_ttl_seconds) and
      recent?(s.passkey_verified_at, now, @admin_ttl_seconds)
  end

  @doc "Whether the email code was given in this session a few minutes ago."
  def fresh_code?(%__MODULE__{code_verified_at: at}, now),
    do: recent?(at, now, @fresh_code_seconds)

  @doc "When the administration closes again for this session, or nil."
  def admin_until(%__MODULE__{} = s) do
    case {s.code_verified_at, s.passkey_verified_at} do
      {nil, _} -> nil
      {_, nil} -> nil
      {a, b} -> [a, b] |> Enum.min(DateTime) |> DateTime.add(@admin_ttl_seconds)
    end
  end

  defp recent?(nil, _now, _ttl), do: false
  defp recent?(at, now, ttl), do: DateTime.diff(now, at) < ttl
end
