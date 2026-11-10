defmodule SyliAtlasWeb.Build do
  @moduledoc """
  Identifier of the code that is running: the deployed commit when the
  platform gives it (RAILWAY_GIT_COMMIT_SHA), else the boot time. Pages and
  the service worker carry it, so a browser can tell a new version is out.
  """

  @key {__MODULE__, :id}

  def id do
    case :persistent_term.get(@key, nil) do
      nil ->
        id =
          case System.get_env("RAILWAY_GIT_COMMIT_SHA") do
            sha when is_binary(sha) and byte_size(sha) >= 7 -> binary_part(sha, 0, 12)
            _ -> "boot-" <> Integer.to_string(System.system_time(:second), 36)
          end

        :persistent_term.put(@key, id)
        id

      id ->
        id
    end
  end

  @doc "What a page was built from: code and data. Changes when either does."
  def version, do: id() <> "." <> data_tag()

  defp data_tag,
    do:
      {SyliAtlas.Profiles.data_version(), SyliAtlas.Market.data_version()}
      |> :erlang.phash2()
      |> Integer.to_string(36)
end
