defmodule PsqlTetris.MigrationRewriter do
  @moduledoc """
  Text-level rewriter for Ecto migration source files.

  Scans for `create table(...) do ... end` and `alter table(...) do ... end` blocks and reorders contiguous runs of `add/2,3` calls inside them, using `PsqlTetris.Optimizer`.

  A couple of deliberate choices worth knowing about:

    * The original file text is preserved everywhere except inside the bodies we explicitly touch. Comments, blank lines, `timestamps()`, `modify/3`, `remove/2`, `index/2` and friends are passed through verbatim and act as barriers that split `add` runs into separate groups. The reason is intent: a comment or a blank line above a column is usually a deliberate grouping signal from the author, and we should not flatten it.
    * Type classification is done by parsing each `add` call with `Code.string_to_quoted/1`. If a call fails to parse (an unusual sigil or heredoc, say), it is left exactly where it was. Better untouched than misordered.
  """

  alias PsqlTetris.Optimizer

  @block_start ~r/^(\s*)(?:create|alter)\s+table\b.*\bdo\s*$/
  @add_start ~r/^\s*add[\s(]/
  # Opt-out marker. Placed anywhere inside a `create/alter table` body it
  # disables reordering for that block. Idea borrowed from Angelika Cathor's
  # markdown code block formatter:
  # https://angelika.me/2024/01/27/format-elixir-code-blocks-in-markdown/
  @skip_marker ~r/^\s*#\s*psql_tetris:\s*skip\b/

  @spec rewrite(String.t()) :: String.t()
  def rewrite(source) when is_binary(source) do
    trailing_newline? = String.ends_with?(source, "\n")
    lines = String.split(source, "\n")
    out = walk(lines, [], :outside, [], nil)
    result = Enum.join(out, "\n")

    cond do
      trailing_newline? and not String.ends_with?(result, "\n") ->
        result <> "\n"

      not trailing_newline? and String.ends_with?(result, "\n") ->
        String.trim_trailing(result, "\n")

      true ->
        result
    end
  end

  # walk(lines, acc_lines_reversed, state, body_lines_in_order_for_inside, indent)

  defp walk([], acc, :outside, _body, _indent), do: Enum.reverse(acc)

  defp walk([], acc, {:inside, _indent}, body, _) do
    # unterminated block: emit body verbatim
    Enum.reverse(acc) ++ body
  end

  defp walk([line | rest], acc, :outside, _body, _indent) do
    case Regex.run(@block_start, line) do
      [_, indent] ->
        walk(rest, [line | acc], {:inside, indent}, [], indent)

      nil ->
        walk(rest, [line | acc], :outside, [], nil)
    end
  end

  defp walk([line | rest], acc, {:inside, indent} = st, body, _) do
    end_pattern = ~r/^#{Regex.escape(indent)}end\s*$/

    if Regex.match?(end_pattern, line) do
      reordered = reorder_body(body)
      new_acc = [line | Enum.reverse(reordered) ++ acc]
      walk(rest, new_acc, :outside, [], nil)
    else
      walk(rest, acc, st, body ++ [line], indent)
    end
  end

  # -- body reordering --------------------------------------------------------

  @doc false
  def reorder_body(lines) do
    if Enum.any?(lines, &Regex.match?(@skip_marker, &1)) do
      lines
    else
      items = group(lines, :gap, [], [])

      items
      |> Enum.reverse()
      |> chunk_by_kind()
      |> Enum.flat_map(fn
        {:add, runs} -> runs |> sort_run() |> Enum.flat_map(& &1.lines)
        {:other, runs} -> Enum.flat_map(runs, & &1.lines)
      end)
    end
  end

  defp group([], :gap, buf, items), do: finalize_gap(buf, items)

  defp group([], :in_add, buf, items) do
    # buf never closed as a valid add: emit as other
    finalize_gap(buf, items)
  end

  defp group([line | rest], :gap, buf, items) do
    if Regex.match?(@add_start, line) do
      items_with_gap = finalize_gap(buf, items)

      if parses?([line]) do
        group(rest, :gap, [], [build_add([line]) | items_with_gap])
      else
        group(rest, :in_add, [line], items_with_gap)
      end
    else
      group(rest, :gap, [line | buf], items)
    end
  end

  defp group([line | rest], :in_add, buf, items) do
    new_buf = [line | buf]
    ordered = Enum.reverse(new_buf)

    if parses?(ordered) do
      group(rest, :gap, [], [build_add(ordered) | items])
    else
      group(rest, :in_add, new_buf, items)
    end
  end

  defp finalize_gap([], items), do: items
  defp finalize_gap(buf, items), do: [build_other(Enum.reverse(buf)) | items]

  defp build_other(lines), do: %{kind: :other, lines: lines}

  defp build_add(lines) do
    info = parse_add(Enum.join(lines, "\n"))
    %{kind: :add, lines: lines, type: info.type, opts: info.opts}
  end

  defp parses?(lines) do
    case Code.string_to_quoted(Enum.join(lines, "\n")) do
      {:ok, _} -> true
      _ -> false
    end
  end

  defp parse_add(text) do
    case Code.string_to_quoted(String.trim(text)) do
      {:ok, {:add, _, args}} when is_list(args) and length(args) >= 2 ->
        [_name, type | rest] = args

        opts =
          case rest do
            [kw] when is_list(kw) -> normalize_opts(kw)
            _ -> []
          end

        %{type: simplify_type(type), opts: opts}

      _ ->
        %{type: :unknown, opts: []}
    end
  end

  defp simplify_type({:references, _meta, args}) when is_list(args) do
    opts =
      case args do
        [_target] -> []
        [_target, kw] when is_list(kw) -> normalize_opts(kw)
        _ -> []
      end

    {:references, opts}
  end

  defp simplify_type(atom) when is_atom(atom), do: atom
  defp simplify_type({tag, _, ctx}) when is_atom(tag) and is_atom(ctx), do: tag
  defp simplify_type({:__block__, _, [v]}), do: simplify_type(v)
  defp simplify_type(other), do: other

  defp normalize_opts(kw) do
    Enum.map(kw, fn
      {k, v} when is_atom(k) -> {k, v}
      other -> other
    end)
  end

  defp chunk_by_kind(items) do
    items
    |> Enum.chunk_by(& &1.kind)
    |> Enum.map(fn run -> {hd(run).kind, run} end)
  end

  defp sort_run(adds) do
    Optimizer.optimize(adds)
  end
end
