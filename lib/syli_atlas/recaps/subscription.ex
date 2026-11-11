defmodule SyliAtlas.Recaps.Subscription do
  @moduledoc """
  An address that asked for the country recap, without an account: the
  chosen countries, the frequency and the language. See `docs/recap.md`
  for what is stored and for how long.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @frequencies ~w(weekly monthly)
  @max_countries 10

  schema "recap_subscriptions" do
    field :email, :string
    field :countries, {:array, :string}, default: []
    field :frequency, :string, default: "weekly"
    field :locale, :string, default: "fr"
    field :confirmed_at, :utc_datetime
    field :last_sent_on, :date

    timestamps(type: :utc_datetime)
  end

  def frequencies, do: @frequencies
  def max_countries, do: @max_countries

  def confirmed?(%__MODULE__{confirmed_at: at}), do: at != nil

  @doc """
  The choices of a form: countries (known codes only, at most
  #{@max_countries}, duplicates dropped), frequency and language. The address
  is set by the caller, already normalised.
  """
  def choices_changeset(subscription, attrs, known_codes) do
    subscription
    |> cast(attrs, [:countries, :frequency, :locale])
    |> update_change(:countries, &clean_countries/1)
    |> validate_required([:email])
    |> validate_length(:countries, max: @max_countries)
    |> validate_some_country()
    |> validate_subset(:countries, known_codes)
    |> validate_inclusion(:frequency, @frequencies)
    |> validate_inclusion(:locale, ["fr", "en"])
    |> unique_constraint(:email)
  end

  # validate_length skips an empty list equal to the default: check the field.
  defp validate_some_country(changeset) do
    case get_field(changeset, :countries) do
      [_ | _] -> changeset
      _ -> add_error(changeset, :countries, "choose at least one country")
    end
  end

  defp clean_countries(codes) when is_list(codes),
    do:
      codes
      |> Enum.map(&String.upcase(String.trim(&1)))
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

  defp clean_countries(_other), do: []
end
