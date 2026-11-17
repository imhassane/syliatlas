defmodule SyliAtlas.Repo.Migrations.SocialPostsPagesAndBufferSync do
  use Ecto.Migration

  # Posts for any page of the site (kind « page », shared from the page
  # itself), the queue without a date (status « ready »), and what Buffer
  # says of each network: when it is due, when it went out, its figures.
  def change do
    alter table(:social_posts) do
      add :page_path, :string
      add :x_due_at, :utc_datetime
      add :x_sent_at, :utc_datetime
      add :x_metrics, :map
      add :linkedin_due_at, :utc_datetime
      add :linkedin_sent_at, :utc_datetime
      add :linkedin_metrics, :map
      add :synced_at, :utc_datetime
    end

    create index(:social_posts, [:page_path])
  end
end
