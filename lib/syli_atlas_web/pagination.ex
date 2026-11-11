defmodule SyliAtlasWeb.Pagination do
  @moduledoc """
  Lists and tables show 10 rows at most; longer ones are paged through the
  URL (`?page=2`), so pages stay cacheable and work without JavaScript.
  """

  @per_page 10

  defstruct entries: [], page: 1, pages: 1, total: 0, offset: 0, per_page: @per_page

  def per_page, do: @per_page

  @doc "The page `page` (clamped to the existing pages) of `list`."
  def paginate(list, page, per_page \\ @per_page) do
    total = length(list)
    pages = max(div(total + per_page - 1, per_page), 1)
    page = page |> to_page() |> min(pages) |> max(1)
    offset = (page - 1) * per_page

    %__MODULE__{
      entries: Enum.slice(list, offset, per_page),
      page: page,
      pages: pages,
      total: total,
      offset: offset,
      per_page: per_page
    }
  end

  @doc """
  A page read from the database: `total` rows in all, `fetch.(limit, offset)`
  reads the rows of the page (clamped to the existing pages).
  """
  def from_count(total, page, fetch, per_page \\ @per_page) when is_function(fetch, 2) do
    pages = max(div(total + per_page - 1, per_page), 1)
    page = page |> to_page() |> min(pages) |> max(1)
    offset = (page - 1) * per_page

    %__MODULE__{
      entries: fetch.(per_page, offset),
      page: page,
      pages: pages,
      total: total,
      offset: offset,
      per_page: per_page
    }
  end

  @doc "Page holding the first item matching `fun` (1 when none does)."
  def page_of(list, fun, per_page \\ @per_page) do
    case Enum.find_index(list, fun) do
      nil -> 1
      i -> div(i, per_page) + 1
    end
  end

  @doc "Parses a page parameter; anything invalid is page 1."
  def to_page(n) when is_integer(n), do: n

  def to_page(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n > 0 -> n
      _ -> 1
    end
  end

  def to_page(_), do: 1

  @doc """
  Page numbers to show: always the first and last, the current one and its
  neighbours; `:gap` where numbers are skipped.
  """
  def window(%__MODULE__{page: page, pages: pages}) do
    [1, page - 1, page, page + 1, pages]
    |> Enum.filter(&(&1 >= 1 and &1 <= pages))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.chunk_every(2, 1)
    |> Enum.flat_map(fn
      [a, b] when b - a > 1 -> [a, :gap]
      [a | _] -> [a]
    end)
  end

  @doc "A URL to `path` with `params` and `key` set to the page, plus an anchor."
  def href(path, params, key, page, anchor \\ nil) do
    query =
      params
      |> Map.put(key, page)
      |> Enum.reject(fn {k, v} -> v in [nil, ""] or (k == key and page == 1) end)
      |> Enum.sort()
      |> URI.encode_query()

    path <> if(query == "", do: "", else: "?" <> query) <> if(anchor, do: "#" <> anchor, else: "")
  end
end
