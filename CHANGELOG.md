# Change Log

## 2.0.5 - 2022-04-12
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
