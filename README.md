# Paginate

Cursor-based and offset-based pagination helpers for Ecto queries.

`Paginate` builds paginated Ecto queries and shapes the results into a
`%{data: ..., meta: ...}` map. It supports two pagination strategies:

* `:cursor` - keyset pagination. Efficient for large datasets since it
  avoids `OFFSET` scans, but does not support random page access.
* `:offset` - classic page/offset pagination. Supports jumping to an
  arbitrary page, at the cost of increasingly expensive queries for deep
  pages.

## Installation

Add `paginate` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:paginate, "~> 0.1.0"}
  ]
end
```

## Usage

### Cursor pagination

```elixir
query = Paginate.query(Post, :cursor, page_size: 25)
posts = Repo.all(query)

Paginate.build_page_result(posts, :cursor, %{
  cursor_field: :id,
  page_size: 25
})
#=> %{data: [...], meta: %{next_cursor: 125, page_size: 25}}

# Fetch the next page using the cursor from the previous result
Paginate.query(Post, :cursor, page_size: 25, cursor: 125)
```

### Offset pagination

```elixir
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
```

Full documentation is available at <https://hexdocs.pm/paginate>.

## License

Copyright 2026 Ryan Winchester

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
