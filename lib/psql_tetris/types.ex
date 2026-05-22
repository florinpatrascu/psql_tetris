defmodule PsqlTetris.Types do
  @moduledoc """
  Classifies Ecto migration column types into PostgreSQL alignment groups.

  ## Strategy

  Two layers, tried in order:

    1. **Ecto translation** (preferred). If `Ecto.Adapters.Postgres.Connection` is loaded (the usual case when the formatter is running inside a Phoenix/Ecto project), we ask Ecto itself to render the PostgreSQL column type for the given migration type, then map the resulting PG type name to its catalog alignment class. This keeps us in lockstep with whatever Ecto version the host project uses, with no duplicated mapping that could rot over time.

    2. **Static fallback**. If Ecto is not loaded (running stand-alone, or the project simply doesn't depend on `ecto_sql`), we fall back to a built-in table that mirrors Ecto's documented mapping. Same logical result for common types: think of it as an intentional safety net for projects we can't introspect.

  ## Alignment classes

    * 1: 8-byte aligned, fixed length (`bigint`, `timestamp[tz]`, `float8`, ...)
    * 2: 4-byte aligned, fixed length (`integer`, `date`, `time`, `uuid`, ...)
    * 3: 2-byte aligned, fixed length (`smallint`)
    * 4: 1-byte aligned, fixed length (`boolean`, `"char"`)
    * 5: variable length (`text`, `varchar`, `numeric`, `jsonb`, `bytea`, arrays)

  Lower rank = larger alignment = emitted first.
  """

  @ecto_conn Ecto.Adapters.Postgres.Connection

  @doc "Returns the alignment rank (1..5) for a migration type."
  @spec rank(term()) :: 1..5
  def rank(type), do: rank(type, [])

  @doc """
  Like `rank/1`, but also takes the keyword list of options passed to `add/3`. This lets shapes like `add :user_id, references(:users, type: :integer)` route through the right alignment class.
  """
  @spec rank(term(), keyword()) :: 1..5
  def rank({:references, inner_opts}, opts) when is_list(inner_opts) do
    type =
      Keyword.get(inner_opts, :type) ||
        Keyword.get(opts, :type, :id)

    # The referenced column's own type tells us how to align the FK column.
    rank(type, [])
  end

  def rank({:array, _inner}, _opts), do: 5

  def rank(type, opts) do
    case ecto_pg_type(type, opts) do
      {:ok, pg_type} -> rank_pg_type(pg_type)
      :error -> static_rank(type)
    end
  end

  @doc "Human-readable label for a rank, used in diagnostics/comments."
  @spec label(1..5) :: String.t()
  def label(1), do: "8-byte aligned"
  def label(2), do: "4-byte aligned"
  def label(3), do: "2-byte aligned"
  def label(4), do: "1-byte aligned"
  def label(5), do: "variable length"

  # -- Ecto-backed path -------------------------------------------------------

  defp ecto_pg_type(type, opts) do
    if Code.ensure_loaded?(@ecto_conn) and function_exported?(@ecto_conn, :column_type, 2) do
      try do
        {:ok, apply(@ecto_conn, :column_type, [type, opts])}
      rescue
        _ -> :error
      catch
        _, _ -> :error
      end
    else
      :error
    end
  end

  # Map a PG type name (possibly with size/precision suffix or `[]`) to its
  # catalog alignment class. The PG catalog values themselves are stable; this
  # table follows `pg_type.typalign` ('d', 'i', 's', 'c') plus a varlena bucket.
  @doc false
  @spec rank_pg_type(String.t()) :: 1..5
  def rank_pg_type(pg_type) when is_binary(pg_type) do
    downcased = String.downcase(pg_type)

    if String.ends_with?(downcased, "[]") do
      5
    else
      downcased
      |> String.replace(~r/\s*\(.*$/, "")
      |> classify_pg_base()
    end
  end

  # PostgreSQL catalog alignment (pg_type.typalign):
  #   'd' = 8-byte, 'i' = 4-byte, 's' = 2-byte, 'c' = 1-byte
  # Names below match what Ecto emits via column_type/2.
  defp classify_pg_base("bigint"), do: 1
  defp classify_pg_base("bigserial"), do: 1
  defp classify_pg_base("int8"), do: 1
  defp classify_pg_base("serial8"), do: 1
  defp classify_pg_base("double precision"), do: 1
  defp classify_pg_base("float8"), do: 1
  defp classify_pg_base("timestamp"), do: 1
  defp classify_pg_base("timestamptz"), do: 1
  defp classify_pg_base("timestamp without time zone"), do: 1
  defp classify_pg_base("timestamp with time zone"), do: 1
  defp classify_pg_base("interval"), do: 1
  defp classify_pg_base("time with time zone"), do: 1
  defp classify_pg_base("timetz"), do: 1
  defp classify_pg_base("money"), do: 1

  defp classify_pg_base("integer"), do: 2
  defp classify_pg_base("int"), do: 2
  defp classify_pg_base("int4"), do: 2
  defp classify_pg_base("serial"), do: 2
  defp classify_pg_base("serial4"), do: 2
  defp classify_pg_base("date"), do: 2
  defp classify_pg_base("time"), do: 2
  defp classify_pg_base("time without time zone"), do: 2
  defp classify_pg_base("real"), do: 2
  defp classify_pg_base("float4"), do: 2
  defp classify_pg_base("oid"), do: 2
  defp classify_pg_base("uuid"), do: 2

  defp classify_pg_base("smallint"), do: 3
  defp classify_pg_base("int2"), do: 3
  defp classify_pg_base("smallserial"), do: 3
  defp classify_pg_base("serial2"), do: 3

  defp classify_pg_base("boolean"), do: 4
  defp classify_pg_base("bool"), do: 4
  defp classify_pg_base("\"char\""), do: 4
  defp classify_pg_base("char"), do: 5
  defp classify_pg_base("character"), do: 5

  # everything else (text, varchar, numeric, decimal, jsonb, json, bytea, ...)
  defp classify_pg_base(_), do: 5

  # -- Static fallback path ---------------------------------------------------
  # Used when Ecto isn't loaded. Mirrors Ecto's documented mapping for common
  # types; keep in sync if Ecto adds/changes mappings.

  defp static_rank(type) do
    case type do
      # 8-byte
      :bigint -> 1
      :bigserial -> 1
      :id -> 1
      :float -> 1
      :double -> 1
      :utc_datetime -> 1
      :utc_datetime_usec -> 1
      :naive_datetime -> 1
      :naive_datetime_usec -> 1
      :timestamp -> 1
      :timestamptz -> 1
      :interval -> 1
      :time_usec -> 1
      :money -> 1
      # 4-byte
      :integer -> 2
      :serial -> 2
      :int -> 2
      :int4 -> 2
      :date -> 2
      :time -> 2
      :float4 -> 2
      :real -> 2
      :oid -> 2
      :uuid -> 2
      :binary_id -> 2
      # 2-byte
      :smallint -> 3
      :int2 -> 3
      # 1-byte
      :boolean -> 4
      :bool -> 4
      # varlena (default)
      _ -> 5
    end
  end
end
