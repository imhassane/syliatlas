defmodule SyliAtlasWeb.PaginationTest do
  use ExUnit.Case, async: true
  alias SyliAtlasWeb.Pagination

  test "pages of 10, clamped" do
    list = Enum.to_list(1..54)
    assert %{entries: [11 | _], page: 2, pages: 6, offset: 10} = Pagination.paginate(list, "2")
    assert %{page: 6, entries: [51, 52, 53, 54]} = Pagination.paginate(list, "99")
    assert %{page: 1} = Pagination.paginate(list, "abc")
    assert %{page: 1, pages: 1} = Pagination.paginate([], nil)
  end

  test "page holding an item" do
    assert Pagination.page_of(Enum.to_list(1..54), &(&1 == 23)) == 3
    assert Pagination.page_of([1, 2], &(&1 == 9)) == 1
  end

  test "numbers around the current page" do
    assert Pagination.window(Pagination.paginate(Enum.to_list(1..90), 5)) == [
             1,
             :gap,
             4,
             5,
             6,
             :gap,
             9
           ]

    assert Pagination.window(Pagination.paginate(Enum.to_list(1..20), 1)) == [1, 2]
  end

  test "links keep the other parameters and drop page 1" do
    assert Pagination.href("/fr/classement", %{"from" => "2015"}, "page", 2, "ranking") ==
             "/fr/classement?from=2015&page=2#ranking"

    assert Pagination.href("/fr/classement", %{"page" => "3"}, "page", 1) == "/fr/classement"
  end
end
