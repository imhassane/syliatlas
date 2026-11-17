defmodule SyliAtlas.Social.Post do
  @moduledoc """
  A post for X (in English) and LinkedIn (in French), prepared from one event
  of the site (`SyliAtlas.Social.Drafts`).

  `status`: `draft` (waiting in /admin/reseaux), `approved` (sending),
  `done` (every chosen network answered), `rejected`. Each network keeps its
  own outcome: `x_state` / `linkedin_state` is nil (not chosen), `queued`
  (in Buffer's queue, `*_ref` = Buffer's post id), `simulated` (no Buffer:
  development), `failed` (`*_error`).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(rating budget_law edition rebasing national)
  @networks ~w(x linkedin)

  def kinds, do: @kinds
  def networks, do: @networks

  # X counts every link as 23 characters.
  @x_limit 280
  @x_link 23
  @linkedin_limit 3000

  def x_limit, do: @x_limit

  schema "social_posts" do
    field :key, :string
    field :kind, :string
    field :area_code, :string
    field :priority, :integer, default: 0
    field :status, :string, default: "draft"
    field :text_x, :string
    field :text_linkedin, :string
    field :link_x, :string
    field :link_linkedin, :string
    field :image_url, :string
    field :image_url_x, :string
    field :x_state, :string
    field :x_ref, :string
    field :x_error, :string
    field :linkedin_state, :string
    field :linkedin_ref, :string
    field :linkedin_error, :string
    field :reviewed_by, :string
    field :reviewed_at, :utc_datetime
    field :sent_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  @doc "A draft prepared by the site."
  def draft_changeset(post, attrs) do
    post
    |> cast(
      attrs,
      ~w(key kind area_code priority text_x text_linkedin link_x link_linkedin image_url image_url_x)a
    )
    |> validate_required(~w(key kind text_x text_linkedin)a)
    |> validate_inclusion(:kind, @kinds)
    |> validate_texts()
    |> unique_constraint(:key)
  end

  @doc "A person rewrites the texts of a draft."
  def edit_changeset(post, attrs) do
    post
    |> cast(attrs, ~w(text_x text_linkedin)a)
    |> validate_required(~w(text_x text_linkedin)a)
    |> validate_texts()
  end

  defp validate_texts(changeset) do
    changeset
    |> validate_change(:text_x, fn :text_x, text ->
      if x_length(text, get_field(changeset, :link_x)) > @x_limit,
        do: [text_x: "dépasse #{@x_limit} caractères sur X"],
        else: []
    end)
    |> validate_length(:text_linkedin, max: @linkedin_limit)
  end

  @doc "The text as sent to X: the link on its own line at the end."
  def x_body(%__MODULE__{text_x: text, link_x: nil}), do: text
  def x_body(%__MODULE__{text_x: text, link_x: link}), do: text <> "\n" <> link

  @doc """
  The text as sent to LinkedIn: the link at the end. Buffer's free plan
  refuses a first comment; drafts written before this change said « lien en
  premier commentaire » and are reworded on the way.
  """
  def linkedin_body(%__MODULE__{text_linkedin: text, link_linkedin: link}) do
    text = String.replace(text, "lien en premier commentaire", "lien ci-dessous")
    if link, do: text <> "\n" <> link, else: text
  end

  @doc """
  The share image for X: the English page's. Drafts written before it was
  stored get it from their English link.
  """
  def x_image(%__MODULE__{image_url_x: url}) when is_binary(url), do: url

  def x_image(%__MODULE__{link_x: link, image_url: fallback}) when is_binary(link) do
    case URI.parse(link) do
      %URI{path: "/" <> _ = path} -> SyliAtlasWeb.Seo.image(path)
      _ -> fallback
    end
  end

  def x_image(%__MODULE__{image_url: url}), do: url

  @doc "Characters counted by X (the link counts 23, wherever it points)."
  def x_length(%__MODULE__{text_x: text, link_x: link}), do: x_length(text, link)

  def x_length(text, nil), do: String.length(text || "")
  def x_length(text, _link), do: String.length(text || "") + 1 + @x_link
end
