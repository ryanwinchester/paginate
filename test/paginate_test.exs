defmodule PaginateTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  doctest Paginate

  describe "query/4 with :cursor" do
    test "first page has no cursor filter beyond `true`" do
      query = Paginate.query("posts", :cursor, page_size: 25)

      assert %Ecto.Query{} = query
      assert query.limit.params == [{26, :integer}]
    end

    test "fetches page_size + 1 rows" do
      query = Paginate.query("posts", :cursor, page_size: 10)
      assert query.limit.params == [{11, :integer}]
    end

    test "applies ascending cursor comparison by default" do
      query = Paginate.query("posts", :cursor, page_size: 10, cursor: 100)

      assert [%Ecto.Query.BooleanExpr{expr: expr}] = query.wheres
      assert Macro.to_string(expr) =~ ">"
    end

    test "applies descending cursor comparison for desc order" do
      query =
        Paginate.query("posts", :cursor,
          page_size: 10,
          order_by: [desc: :id],
          cursor: 100
        )

      assert [%Ecto.Query.BooleanExpr{expr: expr}] = query.wheres
      assert Macro.to_string(expr) =~ "<"
    end

    test "accepts a bare atom order_by" do
      query = Paginate.query("posts", :cursor, page_size: 10, order_by: :id, cursor: 5)

      assert [%Ecto.Query.BooleanExpr{expr: expr}] = query.wheres
      assert Macro.to_string(expr) =~ ">"
    end

    test "raises on invalid order_by" do
      assert_raise ArgumentError, ~r/cursor pagination requires order_by/, fn ->
        Paginate.query("posts", :cursor, page_size: 10, order_by: [{:foo, :id}])
      end
    end
  end

  describe "query/4 with :offset" do
    test "applies offset and limit" do
      query = Paginate.query("posts", :offset, page: 3, page_size: 50)

      assert query.offset.params == [{100, :integer}]
      assert query.limit.params == [{50, :integer}]
    end

    test "defaults to page 1 with no offset" do
      query = Paginate.query("posts", :offset, page_size: 50)

      assert query.offset.params == [{0, :integer}]
    end
  end

  describe "build_page_result/3 with :cursor" do
    test "returns next_cursor when an extra record was fetched" do
      data = for id <- 1..4, do: %{id: id}

      result = Paginate.build_page_result(data, :cursor, %{cursor_field: :id, page_size: 3})

      assert result.data == [%{id: 1}, %{id: 2}, %{id: 3}]
      assert result.meta == %{next_cursor: 3, page_size: 3}
    end

    test "returns nil next_cursor on the last page" do
      data = for id <- 1..2, do: %{id: id}

      result = Paginate.build_page_result(data, :cursor, %{cursor_field: :id, page_size: 3})

      assert result.data == data
      assert result.meta == %{next_cursor: nil, page_size: 3}
    end
  end

  describe "build_page_result/3 with :offset" do
    test "includes page and page_size in meta" do
      data = [%{id: 1}, %{id: 2}]

      result = Paginate.build_page_result(data, :offset, page: 2, page_size: 50)

      assert result.data == data
      assert result.meta == %{page: 2, page_size: 50}
    end
  end

  describe "convenience wrappers" do
    test "build_cursor_page_result/2" do
      result = Paginate.build_cursor_page_result([], %{cursor_field: :id, page_size: 3})
      assert result == %{data: [], meta: %{next_cursor: nil, page_size: 3}}
    end

    test "build_offset_page_result/2" do
      result = Paginate.build_offset_page_result([], page: 1, page_size: 3)
      assert result == %{data: [], meta: %{page: 1, page_size: 3}}
    end
  end
end
