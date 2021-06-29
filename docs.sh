#!/bin/bash
set -e

# Setup:
#
#     $ mix escript.install github elixir-lang/ex_doc
#     # install OTP 24+

rebar3 as docs compile
rebar3 as docs edoc
version=0.5.1
ex_doc "telemetry_poller" $version "_build/docs/lib/telemetry_poller/ebin" \
  --source-ref v${version} \
  --config docs.config $@
