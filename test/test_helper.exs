{otp_release, _} = Integer.parse(System.otp_release())

exclude =
  if otp_release < 20 do
    [:dirty_schedulers]
  else
    []
  end

ExUnit.start(exclude: exclude)
