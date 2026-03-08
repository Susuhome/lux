defmodule Lux.Rust.CargoManager do
  @moduledoc """
  Cargo package management: Cargo.toml generation/parsing, dependency resolution,
  version management, build pipeline, and package caching.
  """

  @default_edition "2021"

  @doc "Generate a Cargo.toml string from a config map."
  def generate_toml(config) do
    name = config[:name] || "lux_native"
    version = config[:version] || "0.1.0"
    edition = config[:edition] || @default_edition
    deps = config[:dependencies] || %{}

    toml = """
    [package]
    name = "#{name}"
    version = "#{version}"
    edition = "#{edition}"

    [dependencies]
    #{format_deps(deps)}
    """

    {:ok, String.trim(toml)}
  end

  @doc "Parse a Cargo.toml string into a map."
  def parse_toml(content) when is_binary(content) do
    lines = String.split(content, "\n")
    {result, _section} = Enum.reduce(lines, {%{}, nil}, fn line, {acc, section} ->
      line = String.trim(line)
      cond do
        String.starts_with?(line, "[") ->
          section_name = line |> String.trim_leading("[") |> String.trim_trailing("]") |> String.trim()
          {acc, section_name}
        String.contains?(line, "=") && section != nil ->
          [key, val] = String.split(line, "=", parts: 2)
          key = String.trim(key)
          val = val |> String.trim() |> String.trim("\"")
          section_map = Map.get(acc, section, %{})
          {Map.put(acc, section, Map.put(section_map, key, val)), section}
        true ->
          {acc, section}
      end
    end)
    {:ok, result}
  end

  @doc "Add a dependency to a parsed config."
  def add_dependency(config, name, version, opts \\ %{}) do
    deps = Map.get(config, :dependencies, %{})
    dep = Map.merge(%{version: version}, opts)
    {:ok, Map.put(config, :dependencies, Map.put(deps, name, dep))}
  end

  @doc "Remove a dependency."
  def remove_dependency(config, name) do
    deps = Map.get(config, :dependencies, %{})
    {:ok, Map.put(config, :dependencies, Map.delete(deps, name))}
  end

  @doc "Resolve dependency versions (semver compatibility check)."
  def resolve_dependencies(deps) when is_map(deps) do
    resolved = Enum.map(deps, fn {name, spec} ->
      version = if is_map(spec), do: spec[:version] || "0.0.0", else: to_string(spec)
      {name, %{version: version, compatible: semver_valid?(version)}}
    end)
    conflicts = Enum.filter(resolved, fn {_n, v} -> !v.compatible end)

    if conflicts == [] do
      {:ok, %{resolved: Map.new(resolved), conflicts: []}}
    else
      {:error, %{conflicts: Enum.map(conflicts, &elem(&1, 0))}}
    end
  end

  @doc "Check if a build cache exists for given config hash."
  def cache_key(config) do
    hash = :crypto.hash(:sha256, :erlang.term_to_binary(config)) |> Base.encode16(case: :lower) |> binary_part(0, 16)
    {:ok, hash}
  end

  @doc "Build command for cargo."
  def build_command(opts \\ []) do
    profile = opts[:profile] || :release
    target = opts[:target]
    features = opts[:features] || []

    cmd = ["cargo", "build"]
    cmd = if profile == :release, do: cmd ++ ["--release"], else: cmd
    cmd = if target, do: cmd ++ ["--target", target], else: cmd
    cmd = if features != [], do: cmd ++ ["--features", Enum.join(features, ",")], else: cmd

    {:ok, Enum.join(cmd, " ")}
  end

  @doc "Bump version (major, minor, patch)."
  def bump_version(version, level \\ :patch) do
    case String.split(version, ".") do
      [major, minor, patch] ->
        {maj, _} = Integer.parse(major)
        {min, _} = Integer.parse(minor)
        {pat, _} = Integer.parse(patch)

        new = case level do
          :major -> "#{maj + 1}.0.0"
          :minor -> "#{maj}.#{min + 1}.0"
          :patch -> "#{maj}.#{min}.#{pat + 1}"
        end
        {:ok, new}
      _ -> {:error, :invalid_version}
    end
  end

  defp format_deps(deps) do
    Enum.map_join(deps, "\n", fn {name, spec} ->
      case spec do
        %{version: v, features: f} ->
          features = Enum.map_join(f, ", ", &"\"#{&1}\"")
          "#{name} = { version = \"#{v}\", features = [#{features}] }"
        %{version: v} -> "#{name} = \"#{v}\""
        v when is_binary(v) -> "#{name} = \"#{v}\""
        _ -> "#{name} = \"#{inspect(spec)}\""
      end
    end)
  end

  defp semver_valid?(version) do
    case String.split(version, ".") do
      [_major, _minor, _patch] -> true
      _ -> false
    end
  end
end
