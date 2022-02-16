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
  </tr>
  <tr>
    <td>>= 2.0.0</td>
    <td>>= 0.14.10, < 2 </td>
    <td>>= 2.6</td>
    <td>~> 2.3.2 </td>
    <td>~> 2.13</td>
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


## Changes

See [CHANGELOG](CHANGELOG.md).

## License

Copyright (c) 2021, 2022  Oracle and/or its affiliates.

See [LICENSE](LICENSE.txt) for more details.

