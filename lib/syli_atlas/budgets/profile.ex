defmodule SyliAtlas.Budgets.Profile do
  @moduledoc """
  Who votes a country's budget and where its laws are published. Seeded from
  `priv/data/budget_catalog.json`; once edited in the admin (`edited_at`),
  the file no longer overwrites the row.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(parliament transition none suspended)
  @modes ~w(manual auto)

  def kinds, do: @kinds
  def modes, do: @modes

  @primary_key {:country_code, :string, autogenerate: false}
  schema "budget_profiles" do
    field :legislature_fr, :string
    field :legislature_en, :string
    field :legislature_kind, :string, default: "parliament"
    field :gazette_name, :string
    field :gazette_url, :string
    field :finance_url, :string
    field :verified, :boolean, default: false
    field :collection_mode, :string, default: "manual"
    field :auto_url, :string
    field :auto_pattern, :string
    field :notes, :string
    field :edited_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  @fields ~w(legislature_fr legislature_en legislature_kind gazette_name gazette_url finance_url
             verified collection_mode auto_url auto_pattern notes)a

  def changeset(profile, attrs) do
    profile
    |> cast(attrs, [:country_code | @fields], empty_values: [""])
    |> validate_required([:country_code, :legislature_kind, :collection_mode])
    |> validate_inclusion(:legislature_kind, @kinds)
    |> validate_inclusion(:collection_mode, @modes)
    |> validate_url(:gazette_url)
    |> validate_url(:finance_url)
    |> validate_url(:auto_url)
    |> validate_pattern()
    |> validate_auto()
  end

  @doc "An edit in the admin: the bundled file stops overwriting the row."
  def edit_changeset(profile, attrs) do
    profile
    |> changeset(attrs)
    |> put_change(:edited_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end

  defp validate_url(cs, field) do
    validate_change(cs, field, fn ^field, url ->
      case URI.parse(url) do
        %URI{scheme: "https", host: host} when is_binary(host) and host != "" -> []
        %URI{scheme: "http", host: host} when is_binary(host) and host != "" -> []
        _ -> [{field, "must be an http(s) address"}]
      end
    end)
  end

  defp validate_pattern(cs) do
    validate_change(cs, :auto_pattern, fn :auto_pattern, pattern ->
      case Regex.compile(pattern) do
        {:ok, _} -> []
        {:error, _} -> [auto_pattern: "is not a valid regular expression"]
      end
    end)
  end

  # Watching a page needs the page.
  defp validate_auto(cs) do
    if get_field(cs, :collection_mode) == "auto" and get_field(cs, :auto_url) in [nil, ""],
      do: add_error(cs, :auto_url, "is required to watch a page"),
      else: cs
  end
end
