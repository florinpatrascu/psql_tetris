# Changelog

All notable changes to `psql_tetris` are documented in this file. Format
loosely follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
versioning follows [SemVer](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-05-22

Initial release.

### Added

* `PsqlTetris.Formatter`: `Mix.Tasks.Format` plugin that reorders columns
  in Ecto migration files for optimal PostgreSQL column alignment.
* `PsqlTetris.Types`: Two-layer type classification. Delegates to
  `Ecto.Adapters.Postgres.Connection.column_type/2` when Ecto is loaded,
  with a static fallback table mirroring Ecto's documented mapping.
* `PsqlTetris.MigrationRewriter`: Text-level rewriter that only touches
  `add/2,3` calls inside `create table` and `alter table` blocks. Other
  statements (`modify`, `remove`, `timestamps`, comments, blank lines)
  act as semantic barriers.
* `PsqlTetris.Optimizer`: Pure stable sort by alignment rank, with
  `null: false` columns prioritized within each rank.
* Per-block opt-out via `# psql_tetris: skip` comment.
* PostgreSQL-only safety gate: detects the host project's database engine
  through the presence of the `Postgrex` driver module and refuses to
  run on MySQL/SQLite/MSSQL projects unless explicitly overridden.
* Configuration knobs in `.formatter.exs`:
  * `migration_paths` (glob list, default `["priv/repo/migrations/", "/migrations/"]`).
  * `enabled` (`true | false`, default: auto-detect via `Postgrex`).

[0.1.0]: https://github.com/florinpatrascu/psql_tetris/releases/tag/v0.1.0
