# Change Log

# 2025-07-29
### Changed
- - As per the recent service name change from `Logging Analytics` to `Log Analytics`, updated the relevant documentation and descriptions to reflect the name change.
  - This is a non-breaking change that maintains backward compatibility
  - Updated service references in documentation, decscription, and comments

## 2.0.8 - 2024-11-18
### Added
- Support for new OCI Regions which are not yet supported through OCI Ruby SDK by default.

## 2.0.7 - 2024-10-10
### Added
- Support for timezone override for logs where timezone identifier is missing
- Support for Workload Identity based authorization

## 2.0.6 - 2024-02-05
### Added
- Support for endpoint override for instance principal auth mode.

## 2.0.5 - 2023-04-12
### Added
- Prometheus metrics support for multi worker configuration.
- 'FAQ' section to help customers in triaging issues when encountered.
### Changed
- Supporting both 'memory' and 'file' buffer types. The recommended and default buffer type is still 'file'.
- Using Yajl over default JSON library for handling multi byte character logs gracefully.
- Plugin log defaults to STDOUT
  - 'oci-logging-analytics.log' file will no longer be created when 'plugin_log_location' in match block section is not provided explicitly.
### Bug fix
- 'tag' field not mandatory in filter block.

## 2.0.4 - 2022-06-20
### Changed
- Updated prometheus-client dependency to v4.0.0.

## 2.0.3 - 2022-04-20
### Added
- Added Prometheus-client Api based internal metrics functionality.
### Bug fix
- Fixing minimum required version for OCI Ruby SDK (oci) runtime dependency

## 2.0.2 - 2022-02-17
### Added
- Added required ruby version in gemspec.
- Added spec metadata (Documentation, Source code and Change log) details.
- Added README.md.
- Added CHANGELOG.md.
- Added examples folder with sample config files for reference.
### Changed
- Optimized import of OCI modules to improve load times and memory usage.

## 2.0.0 - 2022-01-17
### Added
- Initial Release.
