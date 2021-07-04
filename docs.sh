#!/bin/bash
set -e

# Setup:
#
#     $ mix escript.install github elixir-lang/ex_doc
#     # install OTP 24+

rebar3 as docs compile
rebar3 as docs edoc
version=1.0.0
ex_doc "telemetry_poller" $version "_build/docs/lib/telemetry_poller/ebin" \
  --prepend-path "_build/docs/lib/telemetry/ebin" \
  --source-ref v${version} \
  --config docs.config $@
