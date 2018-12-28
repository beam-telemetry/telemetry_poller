elixir_vsn = System.version()
{otp_release, _} = Integer.parse(System.otp_release())

exclude =
  if Version.match?(elixir_vsn, "~> 1.5") do
    []
  else
    [:elixir_1_5_child_specs]
  end

exclude =
  if otp_release < 20 do
    [:dirty_schedulers | exclude]
  else
    exclude
  end

ExUnit.start(exclude: exclude)
