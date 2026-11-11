defmodule SyliAtlasWeb.OgImageController do
  @moduledoc """
  `/og/<version>/<page path>.png`: the share image of a public page, drawn on
  the first request (`SyliAtlasWeb.OgImage`), then kept.

  The version (code and data, `SyliAtlasWeb.Build.version/0`) is in the
  address. A new import or deploy changes it, so the pages point to new
  images; an image is never changed, only replaced. Hence:

  - current version: `Cache-Control: public, max-age=31536000, immutable`,
    and the PNG is kept on disk (`:cache_dir`, next to the database in
    production) so a cache that forgot it costs a file read, not a render;
  - an older version still answers, with today's figures, cached 5 minutes
    and not kept.

  At most `@renders` renders run at once (they use the processor and there
  is one instance); beyond that the request waits a little, then gets a 503
  with Retry-After, which crawlers honour.
  """
  use SyliAtlasWeb, :controller

  alias SyliAtlasWeb.OgImage
  alias SyliAtlasWeb.OgImage.Specs

  @renders 4
  @slots {__MODULE__, :slots}

  def show(conn, %{"version" => version, "path" => segments}) do
    with [_ | _] <- segments,
         {:ok, path} <- page_path(segments),
         current? = version == SyliAtlasWeb.Build.version(),
         {:ok, png} <- image(path, current?) do
      conn
      |> put_resp_content_type("image/png", nil)
      |> put_resp_header(
        "cache-control",
        if(current?, do: "public, max-age=31536000, immutable", else: "public, max-age=300")
      )
      |> send_resp(200, png)
    else
      :busy ->
        conn |> put_resp_header("retry-after", "5") |> send_resp(503, "")

      _ ->
        conn |> put_resp_content_type("text/plain") |> send_resp(404, "Not found")
    end
  end

  @doc """
  The PNG of the page at `path`, from the disk cache or drawn now (and kept
  when `keep?`). Also used to prepare images after an import.
  """
  def image(path, keep? \\ true) do
    file = cache_file(path)

    case keep? && File.read(file) do
      {:ok, png} ->
        {:ok, png}

      _ ->
        with %{} = spec <- Specs.for_path(path),
             {:ok, png} <- with_slot(fn -> OgImage.render(spec) end) do
          if keep? do
            File.mkdir_p!(Path.dirname(file))
            File.write!(file <> ".tmp", png)
            File.rename!(file <> ".tmp", file)
          end

          {:ok, png}
        else
          :busy -> :busy
          _ -> :error
        end
    end
  end

  @doc "Removes the images kept for older versions."
  def prune do
    dir = cache_dir()
    current = SyliAtlasWeb.Build.version()

    case File.ls(dir) do
      {:ok, entries} -> for e <- entries, e != current, do: File.rm_rf!(Path.join(dir, e))
      _ -> []
    end

    :ok
  end

  defp page_path(segments) do
    last = List.last(segments)

    if String.ends_with?(last, ".png") do
      path =
        "/" <> Enum.join(List.replace_at(segments, -1, String.trim_trailing(last, ".png")), "/")

      if String.contains?(path, ".."), do: :error, else: {:ok, path}
    else
      :error
    end
  end

  defp cache_dir,
    do:
      Application.get_env(:syli_atlas, __MODULE__, [])[:cache_dir] ||
        Path.join(System.tmp_dir!(), "syli-og")

  defp cache_file(path) do
    name = :crypto.hash(:sha256, path) |> Base.url_encode64(padding: false)
    Path.join([cache_dir(), SyliAtlasWeb.Build.version(), name <> ".png"])
  end

  # A counter of renders in progress; a request waits up to 2 s for a slot.
  defp with_slot(fun, tries \\ 40) do
    ref = slots()

    if :atomics.add_get(ref, 1, 1) <= @renders do
      try do
        fun.()
      after
        :atomics.sub(ref, 1, 1)
      end
    else
      :atomics.sub(ref, 1, 1)

      if tries > 0 do
        Process.sleep(50)
        with_slot(fun, tries - 1)
      else
        :busy
      end
    end
  end

  defp slots do
    case :persistent_term.get(@slots, nil) do
      nil ->
        ref = :atomics.new(1, signed: true)
        :persistent_term.put(@slots, ref)
        ref

      ref ->
        ref
    end
  end
end
