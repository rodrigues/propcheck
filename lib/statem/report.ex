defmodule PropCheck.StateM.Reporter do
  @moduledoc false

  def print_report({history, state, result}, commands, opts \\ []),
    do: pretty_report(result, history, state, commands, opts)

  defp pretty_report(:ok, history, state, commands, opts),
    do: print_pretty_report(
          "All commands were successful and all postconditions were true.",
          :all, history, state, commands, opts
        )

  defp pretty_report(:initialization_error, history, state, commands, opts),
    do: print_pretty_report("Error while evaluating initial state.", :none,
      history, state, commands, opts)

  defp pretty_report({:precondition, false}, history, state, commands, opts) do
    failing_cmd_idx = {:fail_at, length(history)}
    print_pretty_report("Precondition failed.", failing_cmd_idx,
      history, state, commands, opts)
  end

  defp pretty_report({:precondition, exp = {:exception, _, _, _}}, history,
    state, commands, opts) do
    failing_cmd_idx = {:fail_at, length(history)}
    title =  "Precondition crashed:\n" <> inspectx(exp, opts)
    print_pretty_report(title, failing_cmd_idx, history, state, commands, opts)
  end

  defp pretty_report({:postcondition, false}, history, state, commands, opts) do
    failing_cmd_idx = {:fail_at, length(history) - 1}
    print_pretty_report("Postcondition failed.", failing_cmd_idx,
      history, state, commands, opts)
  end

  defp pretty_report({:postcondition, exp = {:exception, _, _, _}}, history,
    state, commands, opts) do
    failing_cmd_idx = {:fail_at, length(history) - 1}
    title =  "Postcondition crashed:\n#{inspectx(exp, opts)}"
    print_pretty_report(title, failing_cmd_idx, history, state, commands, opts)
  end

  defp pretty_report(exp = {:exception, _, _, _}, history, state, commands, opts) do
    failing_cmd_idx = {:fail_at, length(history)}
    history = history ++ [{state, exp}]
    print_pretty_report("Command crashed.", failing_cmd_idx, history, state,
      commands, opts)
  end

  @header String.duplicate("=", 80)
  defp print_pretty_report(title, cmds_to_print, history, state, commands, opts) do
    main = main_section(cmds_to_print, history, state, commands, opts)
    IO.puts """

    #{@header}
    #{title}

    #{main}
    """
  end

  defp main_section(cmds_to_print, history, state, commands, opts)
  defp main_section(:none, _history, _state, _commands, _opts),
    do: ""
  defp main_section(:all, history, state, commands, opts) do
    history_commands = zip_cmds_history(commands, history)
    last_state = last_state_section(state, opts)
    cmds = history_commands |> print_command_lines(false, opts) |> Enum.join("\n")

    """
    Commands:
    #{cmds}
    #{last_state}
    """
  end
  defp main_section({:fail_at, cmd_idx}, history, state, commands, opts) do
    history_commands = zip_cmds_history(commands, history)
    last_state = last_state_section(state, opts)

    # commands before the failing one
    priori_cmds =
      history_commands
      |> Enum.take(cmd_idx)
      |> print_command_lines(false, opts)

    # failing command
    failing_cmd =
      history_commands
      |> Enum.at(cmd_idx)
      |> print_command_line(true, opts)

    cmds = Enum.join priori_cmds ++ [failing_cmd], "\n"
    """
    Commands:
    #{cmds}
    #{last_state}
    """
  end

  defp last_state_section(state, opts) do
    case Keyword.get(opts, :last_state, true) do
      true ->
        """

        Last state:
        #{inspectx state, opts}
        """
      false -> ""
    end
  end

  defp zip_cmds_history(commands, history) do
    zipper = fn cmd, acc ->
      case acc do
        {[], zipped} ->
          {[], [{cmd, nil} | zipped]}

        {[{pre_state, return_val}], zipped} ->
          post_state = nil
          {[], [{cmd, {return_val, pre_state, post_state}} | zipped]}

        {[{pre_state, return_val}, h = {post_state, _} | history], zipped} ->
          {[h|history], [{cmd, {return_val, pre_state, {:just, post_state}}} | zipped]}
      end
    end
    Enum.reduce(commands, {history, []}, zipper)
    |> elem(1)
    |> Enum.reverse
  end

  defp print_command_lines(hist_cmds, failing?, opts) do
    Enum.map(hist_cmds, &print_command_line(&1, failing?, opts))
  end
  defp print_command_line({cmd, history}, failing?, opts) do
    has_history? = match?({_return_val, _pre_state, _post_state}, history)
    print_return_val? = has_history? and Keyword.get(opts, :return_values, true)
    print_pre_state? = has_history? and Keyword.get(opts, :pre_cmd_state, false)
    print_post_state? = has_history? and Keyword.get(opts, :post_cmd_state, true)

    [
      if(print_pre_state?, do: print_pre_state(history, opts), else: ""),
      print_command(cmd, failing?, opts),
      if(print_return_val?, do: print_return_value(history, opts), else: ""),
      if(print_post_state?, do: print_post_state(history, opts), else: ""),
    ]
    |> to_string
  end

  defp print_command(cmd, failing?, opts)
  defp print_command(cmd, false, opts),
    do: indent(pretty_cmd_name(cmd, opts), 3, false) <> "\n"
  defp print_command(cmd, true, opts) do
    cmt =
      [:red, "#! ", :reset]
      |> IO.ANSI.format() |> to_string
    cmd_str =
      [:red, pretty_cmd_name(cmd, opts), :reset]
      |> IO.ANSI.format() |> to_string
    indent(cmd_str, 3, cmt) <> "\n"
  end

  defp print_return_value({return_val, _, _}, opts) do
    comment("->", return_val, opts)
  end

  defp print_pre_state({_, pre_state, _}, opts) do
    comment("Pre state:", pre_state, opts)
  end

  defp print_post_state({_, _, nil}, _opts), do: ""
  defp print_post_state({_, _, {:just, post_state}}, opts) do
    # "\n" <> comment("Post state:", post_state, opts)
    comment("Post state:", post_state, opts)
  end

  defp comment(title, val, opts) do
    str = inspectx(val, opts)
      # |> String.replace("\n", "\n#{indent}")
    # indent <> title <> str <> "\n"
    indent("#{title} #{str}", 10, true) <> "\n"
  end

  defp indent(str, level, commented?)
  defp indent(str, level, false) do
    String.duplicate(" ", level)
    |> do_indent(str)
  end
  defp indent(str, level, true) when level > 2 do
    (String.duplicate(" ", level - 2) <> "# ")
    |> do_indent(str)
  end
  defp indent(str, _level, true),
    do: do_indent("# ", str)

  defp indent(str, level, cmt) when is_binary(cmt) and level > length(cmt) do
    (String.duplicate(" ", level - length(cmt)) <> cmt)
    |> do_indent(str)
  end
  defp indent(str, _level, cmt) when is_binary(cmt),
    do: do_indent(cmt, str)

  defp do_indent(indent, str) do
    str
    |> String.split("\n")
    |> Enum.map(& "#{indent}#{&1}")
    |> Enum.join("\n")
  end

  def pretty_cmds_name(cmds, opts) do
    Enum.map(cmds, &pretty_cmd_name(&1, opts))
  end
  def pretty_cmd_name({:set, {:var, n}, {:call, mod, fun, args}}, opts) do
    args =
      args
      |> Enum.with_index()
      |> Enum.map(fn
        {{:var, m}, _} -> "var#{m}"
        {arg, i} -> case Keyword.get(opts, :cmd_args, true) do
               true -> inspectx(arg, opts)
               false -> "arg#{n}_#{i+1}"
             end
      end)
      |> Enum.join(", ")
    "var#{n} = #{inspect mod}.#{fun}(#{args})"
  end

  def inspectx({:exception, :error, exception, stacktrace}, _opts) do
    Exception.format :error, exception, stacktrace
  end
  def inspectx(x, opts) do
    opts = Keyword.get(opts, :inspect_opts, [])
    default_opts = [
      pretty: true,
      limit: :infinity,
      syntax_colors: syntax_colors()
    ]
    inspect x, Keyword.merge(default_opts, opts)
  end

  defp syntax_colors do
    IEx.Config.color :syntax_colors
  end
end
