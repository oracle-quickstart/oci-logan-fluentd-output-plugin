# OCI Logging Analytics Fluentd Output Plugin


## Overview

OCI Logging Analytics Fluentd output plugin collects event logs, buffer into local file system, periodically creates payload and uploads it to OCI Logging Analytics.

## Installation Instructions

### Prerequisites

Refer [Prerequisites](https://docs.oracle.com/en/learn/oci_logging_analytics_fluentd/#prerequisites)

### Requirements

<table>
  <tr>
    <th>fluent-plugin-oci-logging-analytics</th>
    <th>fluentd</th>
    <th>ruby</th>
    <th>rubyzip</th>
    <th>oci</th>
    <th>prometheus-client</th>
  </tr>
  <tr>
    <td>>= 2.0.0</td>
    <td>>= 0.14.10, < 2 </td>
    <td>>= 2.6</td>
    <td>~> 2.3.2 </td>
    <td>~> 2.16</td>
    <td>~> 2.1.0</td>
  </tr>
</table>

### Installation

Add this line to your application's Gemfile:

    gem 'fluent-plugin-oci-logging-analytics'
   
And then execute:

    $ bundle
   
Or install it manually as:

    $ gem install fluent-plugin-oci-logging-analytics --no-document
    # If you need to install specific version, use -v option
   

## Configuration
 
### Output Plugin Configuration

   - [Output plugin configuration template](https://docs.oracle.com/en/learn/oci_logging_analytics_fluentd/#create-the-fluentd-configuration-file)

   - [Output plugin configuration parameters](https://docs.oracle.com/en/learn/oci_logging_analytics_fluentd/#output-plugin-configuration-parameters)

### Buffer Configuration

   - [Buffer configuration parameters](https://docs.oracle.com/en/learn/oci_logging_analytics_fluentd/#buffer-configuration-parameters)

### Input Plugin Configuration 

The incoming log events must be in a specific format so that the Fluentd plugin provided by Oracle can process the log data, chunk them, and transfer them to OCI Logging Analytics.
 
   - [Verify the format of the incoming log events](https://docs.oracle.com/en/learn/oci_logging_analytics_fluentd/#verify-the-format-of-the-incoming-log-events)
   
   - [Source configuration](https://docs.oracle.com/en/learn/oci_logging_analytics_fluentd/#source--input-plugin-configuration)

### Filter Configuration

Use filter plugin (record_transformer) to transform the input log events to add OCI Logging Analytics specific fields/metadata.

   - [Filter configuration](https://docs.oracle.com/en/learn/oci_logging_analytics_fluentd/#filter-configuration)


## Examples

   - Example configuration that can be used for monitoring [syslog log](examples/syslog.conf)

   - Example configuration that can be used for monitoring [apache error log](examples/apache.conf)

   - Example configuration that can be used for monitoring [kafka log](examples/kafka.conf)

## Start Viewing the Logs in Logging Analytics

Refer [Viewing the Logs in Logging Analytics](https://docs.oracle.com/en/learn/oci_logging_analytics_fluentd/#start-viewing-the-logs-in-logging-analytics)

## Metrics

The plugin emits following metrics in Prometheus format, which provides stats/insights about the data being collected and processed by the plugin. Refer [monitoring-prometheus](https://docs.fluentd.org/monitoring-fluentd/monitoring-prometheus) for details on how to expose these and other various Fluentd metrics to Prometheus (*If the requirement is to collect and monitor core Fluentd and this plugin metrics alone using Prometheus then Step1 and Step2 from the referred document can be skipped*).

    Metric Name: oci_la_fluentd_output_plugin_records_received 
    labels: [:tag,:oci_la_log_group_id,:oci_la_log_source_name,:oci_la_log_set]
    Description: Number of records received by the OCI Logging Analytics Fluentd output plugin.
    Type : Gauge

    Metric Name: oci_la_fluentd_output_plugin_records_valid 
    labels: [:tag,:oci_la_log_group_id,:oci_la_log_source_name,:oci_la_log_set]
    Description: Number of valid records received by the OCI Logging Analytics Fluentd output plugin.
    Type : Gauge 
    
    Metric Name: oci_la_fluentd_output_plugin_records_invalid 
    labels: [:tag,:oci_la_log_group_id,:oci_la_log_source_name,:oci_la_log_set,:reason]
    Description: Number of invalid records received by the OCI Logging Analytics Fluentd output plugin. 
    Type : Gauge
    
    Metric Name: oci_la_fluentd_output_plugin_records_post_error 
    labels: [:tag,:oci_la_log_group_id,:oci_la_log_source_name,:oci_la_log_set,:error_code, :reason]
    Description: Number of records failed posting to OCI Logging Analytics by the Fluentd output plugin.
    Type : Gauge
        
    Metric Name: oci_la_fluentd_output_plugin_records_post_success 
    labels: [:tag,:oci_la_log_group_id,:oci_la_log_source_name,:oci_la_log_set]
    Description: Number of records posted by the OCI Logging Analytics Fluentd output plugin. 
    Type : Gauge  
  
    Metric Name: oci_la_fluentd_output_plugin_chunk_time_to_receive
    labels: [:tag]
    Description: Average time taken by Fluentd to deliver the collected records from Input plugin to OCI Logging Analytics output plugin.
    Type : Histogram  
    
    Metric Name: oci_la_fluentd_output_plugin_chunk_time_to_post 
    labels: [:oci_la_log_group_id]
    Description: Average time taken for posting the received records to OCI Logging Analytics by the Fluentd output plugin.
    Type : Histogram


## Changes

See [CHANGELOG](CHANGELOG.md).

## License

Copyright (c) 2021, 2022  Oracle and/or its affiliates.

See [LICENSE](LICENSE.txt) for more details.

