## Copyright (c) 2021, 2024  Oracle and/or its affiliates.
## The Universal Permissive License (UPL), Version 1.0 as shown at https://oss.oracle.com/licenses/upl/

require 'prometheus/client'
require 'prometheus/client/registry'
require 'prometheus/client/gauge'
require 'prometheus/client/histogram'
require 'singleton'

class PrometheusMetrics
  include Singleton
  attr_accessor :records_received, :records_valid, :records_invalid, :records_error, :records_posted,
                :bytes_received, :bytes_posted, :chunk_time_to_receive, :chunk_time_to_upload
  def initialize
    createMetrics
    registerMetrics
  end
  def createMetrics
    gauge = Prometheus::Client::Gauge
    @records_received = gauge.new(:oci_la_fluentd_output_plugin_records_received, docstring: 'Number of records received by the OCI Logging Analytics Fluentd output plugin.', labels: [:worker_id,:tag,:oci_la_log_group_id,:oci_la_log_source_name,:oci_la_log_set])
    @records_valid = gauge.new(:oci_la_fluentd_output_plugin_records_valid, docstring: 'Number of valid records received by the OCI Logging Analytics Fluentd output plugin.', labels: [:worker_id,:tag,:oci_la_log_group_id,:oci_la_log_source_name,:oci_la_log_set])
    @records_invalid = gauge.new(:oci_la_fluentd_output_plugin_records_invalid, docstring: 'Number of invalid records received by the OCI Logging Analytics Fluentd output plugin.', labels: [:worker_id,:tag,:oci_la_log_group_id,:oci_la_log_source_name,:oci_la_log_set,:reason])
    @records_error = gauge.new(:oci_la_fluentd_output_plugin_records_post_error, docstring: 'Number of records failed posting to OCI Logging Analytics by the Fluentd output plugin.', labels: [:worker_id,:tag,:oci_la_log_group_id,:oci_la_log_source_name,:oci_la_log_set,:error_code, :reason])
    @records_posted = gauge.new(:oci_la_fluentd_output_plugin_records_post_success, docstring: 'Number of records posted by the OCI Logging Analytics Fluentd output plugin.', labels: [:worker_id,:tag,:oci_la_log_group_id,:oci_la_log_source_name,:oci_la_log_set])

    histogram = Prometheus::Client::Histogram
    @chunk_time_to_receive = histogram.new(:oci_la_fluentd_output_plugin_chunk_time_to_receive, docstring: 'Average time taken by Fluentd to deliver the collected records from Input plugin to OCI Logging Analytics output plugin.', labels: [:worker_id,:tag])
    @chunk_time_to_upload = histogram.new(:oci_la_fluentd_output_plugin_chunk_time_to_post, docstring: 'Average time taken for posting the received records to OCI Logging Analytics by the Fluentd output plugin.', labels: [:worker_id,:oci_la_log_group_id])
  end

  def registerMetrics
    registry = Prometheus::Client.registry
    registry.register(@records_received) unless registry.exist?('oci_la_fluentd_output_plugin_records_received')
    registry.register(@records_valid) unless registry.exist?('oci_la_fluentd_output_plugin_records_valid')
    registry.register(@records_invalid) unless registry.exist?('oci_la_fluentd_output_plugin_records_invalid')
    registry.register(@records_error) unless registry.exist?('oci_la_fluentd_output_plugin_records_post_error')
    registry.register(@records_posted) unless registry.exist?('oci_la_fluentd_output_plugin_records_post_success')
    registry.register(@chunk_time_to_receive) unless registry.exist?('oci_la_fluentd_output_plugin_chunk_time_to_receive')
    registry.register(@chunk_time_to_upload) unless registry.exist?('oci_la_fluentd_output_plugin_chunk_time_to_post')
  end
end
