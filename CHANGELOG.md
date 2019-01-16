# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0](https://github.com/beam-telemetry/telemetry_poller/tree/v0.2.0)

### Added

* Added `:total_run_queue_lengths` and `:run_queue_lengths` memory measurements;

### Changed

* `:total_run_queue_lengths` is now included in the set of default VM measurements;
* A default Poller process, with a default set of VM measurements, is started when `:telemetry_poller`
  application starts (configurable via `:telemetry.poller, :default` application environment).
* VM measurements are now provided to Poller's `:vm_measurements` option. Passing atom `:default`
  to this option makes the Poller use a default set of VM measurements;
* Telemetry has been upgraded to version 0.3, meaning that VM measurements now use this version to
  emit the events.

### Removed

* `Telemetry.Poller.vm_measurements/0` function has been removed in favor of `:vm_measurements`
  option.

### Fixed

* Fixed the type definition of `Telemetry.Poller.measurement/0` type - no Dialyzer warnings are
  emitted when running it on the project.

## [0.1.0](https://github.com/beam-telemetry/telemetry_poller/tree/v0.1.0)

### Added

* The Poller process periodically invoking registered functions which emit Telemetry events.
  It supports VM memory measurements and custom measurements provided as MFAs.