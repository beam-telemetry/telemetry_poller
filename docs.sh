#!/bin/bash
set -e

# Setup:
#
#     # 1. install OTP 24+
#     # 2. install ExDoc:
#     $ mix escript.install github elixir-lang/ex_doc

rebar3 as docs compile
rebar3 as docs edoc
version=1.0.0
ex_doc "telemetry_poller" $version "_build/docs/lib/telemetry_poller/ebin" \
  --paths "_build/docs/lib/*/ebin" \
  --source-ref v${version} \
  --config docs.config $@
