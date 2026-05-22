defmodule PsqlTetris do
  @moduledoc """
  PostgreSQL column-tetris formatter for Ecto migrations.

  This package ships a `Mix.Tasks.Format` plugin (`PsqlTetris.Formatter`) that rewrites Ecto migration files so the resulting table's on-disk column layout wastes as few padding bytes as possible. PostgreSQL aligns column values on natural boundaries and slips padding in between, and a "tetris-friendly" column order keeps those gaps small.

  See `PsqlTetris.Formatter` for installation and configuration. You can also call `optimize_migration/1` directly on a migration source string.
  """

  alias PsqlTetris.MigrationRewriter

  @doc ~S'''
  Reorders the columns of every `create table` / `alter table` block in the given Elixir migration source string.

  ## Example

  ```elixir
  source = """
  defmodule MyApp.Repo.Migrations.CreateUsers do
    use Ecto.Migration

    def change do
      create table(:users) do
        add :active, :boolean, null: false
        add :email, :string
        add :id_num, :bigint
      end
    end
  end
  """

  PsqlTetris.optimize_migration(source) |> IO.puts()
  ```
  '''
  @spec optimize_migration(String.t()) :: String.t()
  def optimize_migration(source) when is_binary(source) do
    MigrationRewriter.rewrite(source)
  end
end
