defmodule SyliAtlas.Accounts.User do
  @moduledoc "An account: an email address, a role (member or admin) and its preferences."
  use Ecto.Schema
  import Ecto.Changeset

  @roles ~w(member admin)
  @digests ~w(weekly monthly never)

  schema "users" do
    field :email, :string
    field :role, :string, default: "member"
    field :locale, :string, default: "fr"
    field :digest, :string, default: "weekly"
    field :security_emails, :boolean, default: true
    field :last_sign_in_at, :utc_datetime
    field :deactivated_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def roles, do: @roles
  def digests, do: @digests

  def admin?(%__MODULE__{role: "admin"}), do: true
  def admin?(_user), do: false

  @doc "A new account; the role is set by the caller, never from a form."
  def create_changeset(email, role, locale) do
    %__MODULE__{}
    |> change(email: email, role: role, locale: locale)
    |> validate_inclusion(:role, @roles)
    |> validate_inclusion(:locale, ["fr", "en"])
    |> unique_constraint(:email)
  end

  def preferences_changeset(user, attrs) do
    user
    |> cast(attrs, [:digest, :security_emails, :locale])
    |> validate_inclusion(:digest, @digests)
    |> validate_inclusion(:locale, ["fr", "en"])
  end

  @doc "Lower-cased and trimmed; nil when it does not look like an address."
  def normalize_email(email) when is_binary(email) do
    email = email |> String.trim() |> String.downcase()

    if String.length(email) <= 254 and Regex.match?(~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, email),
      do: email,
      else: nil
  end

  def normalize_email(_email), do: nil
end
