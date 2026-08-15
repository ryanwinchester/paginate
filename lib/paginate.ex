defmodule Paginate do
  @moduledoc """
  Cursor-based and offset-based pagination helpers for Ecto queries.

  `Paginate` builds paginated Ecto queries and shapes the results into a
  `%{data: ..., meta: ...}` map. It supports two pagination strategies:

  * `:cursor` - keyset pagination. Pages are fetched relative to a cursor
    value (typically the primary key or another sortable column). Efficient
    for large datasets since it avoids `OFFSET` scans, but does not support
    random page access.

  * `:offset` - classic page/offset pagination. Supports jumping to an
    arbitrary page, at the cost of increasingly expensive queries for deep
    pages.

  ## Example

      query = Paginate.query(Post, :cursor, page_size: 25, cursor: 100)
      posts = Repo.all(query)

      Paginate.build_page_result(posts, :cursor, %{
        cursor_field: :id,
        page_size: 25
      })
      #=> %{data: [...], meta: %{next_cursor: 125, page_size: 25}}

  ## Defaults

  * `:order_by` - `[asc: :id]`
  * `:page` - `1`
  * `:page_size` - `500`

  """

  import Ecto.Query

  @default_order_by [asc: :id]
  @default_page 1
  @default_page_size 500

  @defaults %{
    order_by: @default_order_by,
    page: @default_page,
    page_size: @default_page_size
  }

  def cursor_query(queryable, opts, defaults \\ @defaults) do
    query(queryable, :cursor, opts, defaults)
  end

  def offset_query(queryable, opts, defaults \\ @defaults) do
    query(queryable, :offset, opts, defaults)
  end

  @doc """
  Builds a paginated `Ecto.Query` from `queryable` using the given
  pagination strategy.

  ## Pagination types

  * `:cursor` - keyset pagination. Filters rows relative to the `:cursor`
    option using the leading `:order_by` column, and fetches
    `page_size + 1` rows so `build_page_result/3` can detect whether a
    next page exists.

  * `:offset` - offset pagination. Applies `OFFSET (page - 1) * page_size`
    and `LIMIT page_size`.

  ## Options

  * `:order_by` - the `order_by` expression for the query. For `:cursor`
    pagination the leading entry must be an atom column, optionally tagged
    with `:asc`/`:desc` (e.g. `[desc: :inserted_at]`), and determines the
    cursor comparison field and direction. Defaults to
    `#{inspect(@default_order_by)}`.

  * `:page_size` - maximum number of records per page. Defaults to
    `#{@default_page_size}`.

  * `:cursor` (`:cursor` only) - the cursor value from the previous page
    (see `next_cursor` in the result meta). When `nil`, the first page is
    returned. Rows are filtered with `>` for ascending order and `<` for
    descending order.

  * `:page` (`:offset` only) - the 1-based page number. Defaults to
    `#{@default_page}`.

  `defaults` can be passed to override the built-in default option values.

  ## Examples

      # First page, cursor pagination
      Paginate.query(Post, :cursor, page_size: 25)

      # Next page, using the cursor from the previous result
      Paginate.query(Post, :cursor, page_size: 25, cursor: 100)

      # Descending cursor pagination on another column
      Paginate.query(Post, :cursor, order_by: [desc: :inserted_at], cursor: ~U[2026-01-01 00:00:00Z])

      # Offset pagination, page 3
      Paginate.query(Post, :offset, page: 3, page_size: 50)

  """
  def query(queryable, pagination_type, opts, defaults \\ @defaults)

  def query(queryable, :cursor, opts, defaults) do
    page_opts = Enum.into(opts, defaults)

    {direction, cursor_field} =
      case page_opts.order_by do
        [{direction, field} | _] when direction in [:asc, :desc] ->
          {direction, field}

        [field | _] when is_atom(field) ->
          {:asc, field}

        field when is_atom(field) ->
          {:asc, field}

        other ->
          raise ArgumentError,
                "cursor pagination requires order_by with a leading " <>
                  ":asc/:desc atom column, got: #{inspect(other)}"
      end

    cursor =
      case {page_opts[:cursor], direction} do
        {nil, _} -> true
        {_, :asc} -> dynamic([q], field(q, ^cursor_field) > ^page_opts.cursor)
        {_, :desc} -> dynamic([q], field(q, ^cursor_field) < ^page_opts.cursor)
      end

    from q in queryable,
      where: ^cursor,
      order_by: ^page_opts.order_by,
      limit: ^(page_opts.page_size + 1)
  end

  def query(queryable, :offset, opts, defaults) do
    page_opts = Enum.into(opts, defaults)

    %{order_by: order_by, page: page, page_size: page_size} = page_opts

    offset = (page - 1) * page_size

    from q in queryable,
      order_by: ^order_by,
      offset: ^offset,
      limit: ^page_size
  end

  @doc """
  Convenience wrapper for `build_page_result(data, :cursor, page_opts)`.

  See `build_page_result/3` for details.
  """
  def build_cursor_page_result(data, page_opts) do
    build_page_result(data, :cursor, page_opts)
  end

  @doc """
  Convenience wrapper for `build_page_result(data, :offset, page_opts)`.

  See `build_page_result/3` for details.
  """
  def build_offset_page_result(data, page_opts) do
    build_page_result(data, :offset, page_opts)
  end

  @doc """
  Shapes query results into a page result map with pagination metadata.

  Returns a map with:

  * `:data` - the records for the current page
  * `:meta` - pagination metadata, depending on the pagination type

  ## Cursor pagination

  Expects `data` to be the result of running a query built with
  `query(queryable, :cursor, ...)`, which fetches one extra record to detect
  whether a next page exists. `page_opts` must be a map with:

  * `:cursor_field` - the column used as the cursor (the leading `:order_by`
    column given to `query/4`)
  * `:page_size` - the page size given to `query/4`

  The extra record is dropped from `:data`. The meta contains:

  * `:next_cursor` - the cursor value to fetch the next page, or `nil`
    when there are no more pages
  * `:page_size` - the page size

  ## Offset pagination

  `page_opts` is a keyword list accepting `:page` and `:page_size` (falling
  back to the module defaults). The meta contains:

  * `:page` - the current page number
  * `:page_size` - the page size

  ## Total count

  For either pagination type, a total count can be included in the meta by
  passing these options in `page_opts`:

  * `:get_total` - when truthy, executes a count aggregate and adds `:total`
    (the total number of records matching `:query`) to the meta
  * `:repo` - the `Ecto.Repo` used to run the count (required with
    `:get_total`)
  * `:query` - the queryable to count (required with `:get_total`). Pass the
    base queryable without limit/offset, otherwise only the current page is
    counted.

  ## Examples

      query = Paginate.query(Post, :cursor, page_size: 25)
      posts = Repo.all(query)

      Paginate.build_page_result(posts, :cursor, %{
        cursor_field: :id,
        page_size: 25
      })
      #=> %{data: [...], meta: %{next_cursor: 125, page_size: 25}}

      query = Paginate.query(Post, :offset, page: 2, page_size: 50)
      posts = Repo.all(query)

      Paginate.build_page_result(posts, :offset,
        page: 2,
        page_size: 50,
        get_total: true,
        repo: Repo,
        query: Post
      )
      #=> %{data: [...], meta: %{page: 2, page_size: 50, total: 1234}}

  """
  def build_page_result(data, pagination_type, page_opts, defaults \\ @defaults)

  def build_page_result(data, :cursor, page_opts, defaults) do
    %{cursor_field: cursor_field, page_size: page_size} = Enum.into(page_opts, defaults)

    {page, peek} = Enum.split(data, page_size)

    next_cursor =
      case peek do
        [] -> nil
        [_] -> List.last(page) |> Map.fetch!(cursor_field)
      end

    %{
      data: page,
      meta:
        %{
          next_cursor: next_cursor,
          page_size: page_size
        }
        |> maybe_include_total(page_opts)
    }
  end

  def build_page_result(data, :offset, page_opts, defaults) do
    page_opts = Enum.into(page_opts, defaults)

    %{
      data: data,
      meta:
        %{
          page: Keyword.get(page_opts, :page, @default_page),
          page_size: Keyword.get(page_opts, :page_size, @default_page_size)
        }
        |> maybe_include_total(page_opts)
    }
  end

  defp maybe_include_total(meta, opts) do
    if Access.get(opts, :get_total) do
      repo = Access.fetch!(opts, :repo)
      query = Access.fetch!(opts, :query)
      Map.put(meta, :total, repo.aggregate(query, :count))
    else
      meta
    end
  end
end
