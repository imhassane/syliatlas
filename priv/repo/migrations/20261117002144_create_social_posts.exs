defmodule SyliAtlas.Repo.Migrations.CreateSocialPosts do
  use Ecto.Migration

  def change do
    # Posts for X and LinkedIn, prepared from the site's events
    # (SyliAtlas.Social): a draft until a person approves it in
    # /admin/reseaux, then sent to Buffer's queue (simulated outside
    # production). One row per event: `key` is unique.
    create table(:social_posts) do
      add :key, :string, null: false
      add :kind, :string, null: false
      add :area_code, :string
      add :priority, :integer, null: false, default: 0
      add :status, :string, null: false, default: "draft"
      add :text_x, :text, null: false
      add :text_linkedin, :text, null: false
      add :link_x, :string
      add :link_linkedin, :string
      add :image_url, :string
      add :x_state, :string
      add :x_ref, :string
      add :x_error, :string
      add :linkedin_state, :string
      add :linkedin_ref, :string
      add :linkedin_error, :string
      add :reviewed_by, :string
      add :reviewed_at, :utc_datetime
      add :sent_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:social_posts, [:key])
    create index(:social_posts, [:status])
  end
end
