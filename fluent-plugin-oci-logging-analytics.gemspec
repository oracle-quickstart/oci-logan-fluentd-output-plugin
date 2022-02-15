## Copyright (c) 2021, 2022  Oracle and/or its affiliates.
## The Universal Permissive License (UPL), Version 1.0 as shown at https://oss.oracle.com/licenses/upl/

lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name    = "fluent-plugin-oci-logging-analytics"
  spec.version = "2.0.0"
  spec.authors = ["Oracle","OCI Observability: Logging Analytics"]
  spec.email   = ["oci_la_plugins@oracle.com"]

  spec.summary       = %q{Fluentd Output plugin to ship logs/events to OCI Logging Analytics.}
  spec.description   = %q{Oracle OCI Logging Analytics fluentd output plugin. Ingests/Ships logs to OCI Logging Analytics}
  spec.license       = "UPL-1.0"

  spec.files         = Dir.glob("{bin,lib}/**/*")
  spec.executables   = spec.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]
  spec.required_ruby_version = ">= 2.6.0"
  spec.metadata = {
    "documentation_uri" => "https://docs.oracle.com/en/learn/oci_logging_analytics_fluentd/"
    "source_code_uri' => 'https://github.com/oracle-quickstart/oci-logan-fluentd-output-plugin",
    "changelog_uri'   => 'https://github.com/oracle-quickstart/oci-logan-fluentd-output-plugin/CHANGELOG.md"
  }

  spec.add_development_dependency "rake", "~> 12.0"
  spec.add_development_dependency "test-unit", "~> 3.0"
  spec.add_runtime_dependency "fluentd", [">= 0.14.10", "< 2"]
  spec.add_runtime_dependency 'rubyzip', '~> 2.3.2'
  spec.add_runtime_dependency "oci", "~>2.13"

end
