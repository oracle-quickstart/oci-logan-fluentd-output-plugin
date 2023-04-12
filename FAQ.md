# Frequently Asked Questions

- [Why am I getting this error - "Error occurred while initializing LogAnalytics Client" ?](#why-am-i-getting-this-error---error-occurred-while-initializing-loganalytics-client-)
- [Why am I getting this error - "Error occurred while parsing oci_la_log_set" ?](#why-am-i-getting-this-error---error-occurred-while-parsing-oci_la_log_set-)
- [Why am I getting this error - "Error while uploading the payload" or "execution expired" or "status : 0" ?](#why-am-i-getting-this-error---error-while-uploading-the-payload-or--execution-expired-or--status--0-)
- [How to find fluentd/output plugin logs ?](#how-to-find-fluentdoutput-plugin-logs-)
- [Fluentd successfully uploaded data, but still it is not visible in LogExplorer. How to triage ?](#fluentd-successfully-uploaded-data-but-still-it-is-not-visible-in-logexplorer-how-to-triage-)
- [How to extract specific K8s metadata field that I am interested in to a Logging Analytics field ?](#how-to-extract-specific-k8s-metadata-field-that-i-am-interested-in-to-a-logging-analytics-field-)
- [How to make Fluentd process the log data from the beginning of a file when using tail input plugin ?](#how-to-make-fluentd-process-the-log-data-from-the-beginning-of-a-file-when-using-tail-input-plugin-)
- [How to make Fluentd process the last line from the file when using tail input plugin ?](#how-to-make-fluentd-process-the-last-line-from-the-file-when-using-tail-input-plugin-)
- [In multi worker setup, prometheus is not displaying all the worker's metrics. How to fix it ?](#in-multi-worker-setup-prometheus-is-not-displaying-all-the-workers-metrics-how-to-fix-it-)
- [Why am I getting this error - "ConcatFilter::TimeoutError" ?](#why-am-i-getting-this-error---concatfiltertimeouterror-)
- [Fluentd is failing to parse the log data. What can be the reason ?](#fluentd-is-failing-to-parse-the-log-data-what-can-be-the-reason-)


## Why am I getting this error - "Error occurred while initializing LogAnalytics Client" ?
- This occurs mostly due to incorrect authorization type/configuration provided. 
- This plugin uses either config based auth or Instance principal based auth with default being Instance principal based auth.
- For config based auth ensure valid "config_file_location" and "profile" details are provided in match block as shown below.
  ```
  <match oci.**>
      @type oci-logging-analytics
      config_file_location       #REPLACE_ME
      profile_name              DEFAULT
  </match>
  ```

## Why am I getting this error - "Error occurred while parsing oci_la_log_set" ?
- The provided Regex do not match the key coming in and the regex might need a correction.
- This might be expected behaviour with the regex configured where not all keys need to be matched. In such scenarios we fall back to use logSet parameter set using oci_la_log_set.
- You may also apply logSet using alternative approach documented [here](https://docs.oracle.com/en-us/iaas/logging-analytics/doc/manage-log-partitioning.html#LOGAN-GUID-2EC8EEDE-9BBD-4872-8083-A44F77611524)

## Why am I getting this error - "Error while uploading the payload" or "execution expired" or "status : 0" ?
- Sample logs:
  ```
  I, [2023-01-18T10:39:49.483789 #11]  INFO -- : Received new chunk, started processing ...
  I, [2023-01-18T10:39:49.495771 #11]  INFO -- : Generating payload with 31  records for oci_la_log_group_id: ocid1.loganalyticsloggroup.oc1.iad.amaaaaaa....
  E, [2023-01-18T10:39:59.502747 #11] ERROR -- : oci upload exception : Error while uploading the payload. { 'message': 'execution expired', 'status': 0, 'opc-request-id':'C37D1DE643E24D778FC5FA22835FE024', 'response-body': '' }
  ```

- This occurs due to connectivity to OCI endpoint. Ensure the proxy details are provided are valid if configured, or you have network connectivity to reach the OCI endpoint from where you are running the fluentd.

## How to find fluentd/output plugin logs ?
- By default (starting from 2.0.5 version), oci logging analytics output plugin logs goes to STDOUT and available as part of the fluentd logs itself, unless it is explicitly configured using the following plugin parameter.
  ```
  plugin_log_location   "#{ENV['FLUENT_OCI_LOG_LOCATION'] || '/var/log'}"
  # Log file named 'oci-logging-analytics.log' will be generated in the above location
  ```
- For td-agent (rpm/deb) based setup, the fluentd logs are located at /var/log/td-agent/td-agent.log


## Fluentd successfully uploaded data, but still it is not visible in LogExplorer. How to triage ?
- Check if selected time range in log explorer is in line with the actual log messages timestamp.
- Check after some time - As the processing of the data happens asynchronously, there are cases it may take some time to reflect the data in log explorer.
  - The processing of the data may fail in the subsequent validations which happens at OCI.
    - Check for any [processing errors](https://docs.oracle.com/en-us/iaas/logging-analytics/doc/troubleshoot-ingestion-pipeline.html).
    - If the issue is still persistent, raise an SR by providing the following information. tenency_ocid, region, sample opc-request-id/opc-object-id
    - You may get the opc-request-id/opc-object-id from fluentd output plugin log. The sample log for a successful upload looks like below,

      ```
      I, [2023-01-18T10:39:49.483789 #11]  INFO -- : Received new chunk, started processing ...
      I, [2023-01-18T10:39:49.495771 #11]  INFO -- : Generating payload with 30  records for oci_la_log_group_id: ocid1.loganalyticsloggroup.oc1.iad.amaaaaaa....
      I, [2023-01-18T10:39:59.502747 #11]  INFO -- : The payload has been successfully uploaded to logAnalytics -
                              oci_la_log_group_id: ocid1.loganalyticsloggroup.oc1.iad.amaaaaaa....,
                              ConsumedRecords: #30,
                              opc-request-id':'C37D1DE643E24D778FC5FA22835FE024',
                              opc-object-id: 'C37D1DE643E24D778FC5FA22835FE024-D37D1DE643E24D778FC5FA22835FE024'"
      ```
## How to extract specific K8s metadata field that I am interested in to a Logging Analytics field ?
- We can get this kind of scenario when collecting the logs from Kubernetes clusters and using kubernetes_metadata_filter to enrich the data at fluentd.
- By default, fluentd output plugin will fetch following fields "container_name", "namespace_name", "pod_name", "container_image", "host" from kubernetes metadata when available, and maps them to following fields "Container", "Namespace", "Pod", "Container Image Name", "Node".
- In case if a new field is needed to be extracted, or to modify the default mappings, add "kubernetes_metadata_keys_mapping" in match block like shown below.
  - When you are adding a new field mapping, ensure the corresponding Loggingg Analytics field is already defined.

      ```
      <match oci.**>
          @type oci-logging-analytics
          nameSpace                 namespace  #REPLACE_ME
          config_file_location      ~/.oci/config #REPLACE_ME
          profile_name              DEFAULT
          kubernetes_metadata_keys_mapping     {"container_name":"Container","namespace_name":"Namespace","pod_name":"Pod","container_image":"Container Image Name","host":"Node"}
          <buffer>
              @type file
              path /var/log/fluent_oci_outplugin/buffer/ #REPLACE_ME
              disable_chunk_backup true
          </buffer>
      </match>
      ```

## How to make Fluentd process the log data from the beginning of a file when using tail input plugin ?
- The default behaviour of the tail plugin is to read from the latest(tail). This behaviour can be altered by modifying the "read_from_head" parameter.
- The below is an example tail plugin configuration to read from beginning of a file named foo.log

  ```
  <source>
      @type tail
      <parse>
          @type none
      </parse>
      path foo.log
      pos_file foo.pos
      tag oci.foo
      read_from_head  true
  </source>
  ```

## How to make Fluentd process the last line from the file when using tail input plugin ?
- In case of multi-line events, for last line, log consumption might be delayed until the next log message is written to the log file. Fluentd will only parse the last line when a line break is appended at the end of the line. 
- To fix this, add/increase multiline_flush_interval property in source block.

  ```
  <source>
      @type tail
      multiline_flush_interval 5s
      <parse>
          @type multiline
          format_firstline /\d{4}-[01]\d-[0-3]\d\s[0-2]\d((:[0-5]\d)?){2}\s+(\w+)\s+\[([\w-]+)?\]\s([\w._$]+)\s+([-\w]+)\s+(.*)/
          format1 /^(?<message>.*)/ 
      </parse>
      path foo.log
      pos_file foo.pos 
      tag oci.foo
      read_from_head  true 
  </source>
  ```

## In multi worker setup, prometheus is not displaying all the worker's metrics. How to fix it ?
- In case of multi worker setup, each worker needs its own port binding. To ensure prometheus engine is scraping metrics from multiple ports, provide "aggregated_metrics_path /aggregated_metrics" in prometheus source config as shown below.
- Multi worker config example

  ```
  <source>
      @type prometheus
      bind 0.0.0.0
      port 24231
      aggregated_metrics_path /aggregated_metrics
  </source> 
  ```

- Single worker config example

  ```
  <source>
      @type prometheus
      bind 0.0.0.0
      port 24231
      metrics_path /metrics
  </source>
  ```

## Why am I getting this error - "ConcatFilter::TimeoutError" ?
- This error occurs when using Concat plugin to handle multiline log messages.
- When the incoming log flow is very slow, then concat plugin throws this error to avoid waiting indefinitely for the next multiline start expression match.
- By increasing the flush_interval for this concat filter to appropriate value, this issue can be avoided.
- We recommend usage of "timeout_label" to redirect the corresponding log messages and handle them appropriately to avoid the data loss.
- When using "timeout_label", you may ignore this error.

  ```
  # Concat filter to handle multi-line log records.
  <filter oci.apache.concat>
      @type concat
      key message
      flush_interval 15
      timeout_label @NORMAL
      multiline_start_regexp /\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}.\d{3}Z/
      separator ""
  </filter>

  <label @NORMAL>
      <match>
          @type oci-logging-analytics
          namespace                   <YOUR_OCI_TENANCY_NAMESPACE>
          config_file_location        ~/.oci/config
          profile_name                DEFAULT
          <buffer>
              @type	file
              path	/var/log
              retry_forever	true
              disable_chunk_backup	true
          </buffer>
      </match>
  </label>  
  ```


## Fluentd is failing to parse the log data. What can be the reason ?
- In the source-block check the regex/format_firstline expression and check if it matches with your log data.
- Sample logs:
  ```
  2021-02-06 01:44:03 +0000 [warn]: #0 dump an error event: 
  error_class=Fluent::Plugin::Parser::ParserError error="pattern not match with data <log message>
  ```
- Multiline

  ```
  <source>
      @type tail
      multiline_flush_interval 5s
      <parse>
          @type multiline
          format_firstline /\d{4}-[01]\d-[0-3]\d\s[0-2]\d((:[0-5]\d)?){2}\s+(\w+)\s+\[([\w-]+)?\]\s([\w._$]+)\s+([-\w]+)\s+(.*)/
          format1 /^(?<message>.*)/
      </parse>
      path foo.log
      pos_file foo.pos
      tag oci.foo
      read_from_head  true
  </source>
  ```

- Regexp

  ```
  <source>
      @type tail
      multiline_flush_interval 5s
      # regexp
      <parse>
          @type regexp
          expression ^(?<name>[^ ]*) (?<user>[^ ]*) (?<age>\d*)$
      </parse>
      path foo.log
      pos_file foo.pos
      tag oci.foo
      read_from_head  true
  </source>
  ```