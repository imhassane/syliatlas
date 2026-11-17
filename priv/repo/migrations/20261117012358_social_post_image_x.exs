defmodule SyliAtlas.Repo.Migrations.SocialPostImageX do
  use Ecto.Migration

  def change do
    # X posts are in English: their share image is the English page's.
    alter table(:social_posts) do
      add :image_url_x, :string
    end
  end
end
