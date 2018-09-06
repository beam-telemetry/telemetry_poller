elixir_vsn = System.version()

config =
  if Version.match?(elixir_vsn, "~> 1.5") do
    []
  else
    [exclude: :elixir_1_5_child_specs]
  end

ExUnit.start(config)
