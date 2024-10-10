## Copyright (c) 2021, 2024  Oracle and/or its affiliates.
## The Universal Permissive License (UPL), Version 1.0 as shown at https://oss.oracle.com/licenses/upl/

require 'fluent/plugin/output'
require "benchmark"
require 'zip'
require 'yajl'
require 'yajl/json_gem'

# require 'tzinfo'
require 'logger'
require_relative '../dto/logEventsJson'
require_relative '../dto/logEvents'
require_relative '../metrics/prometheusMetrics'
require_relative '../metrics/metricsLabels'
require_relative '../enums/source'

# Import only specific OCI modules to improve load times and reduce the memory requirements.
require 'oci/auth/auth'
require 'oci/log_analytics/log_analytics'
require 'oci/log_analytics/log_analytics_client'

# Workaround until OCI SDK releases a proper fix to load only specific service related modules/client.
require 'oci/api_client'
require 'oci/api_client_proxy_settings'
require 'oci/config'
require 'oci/config_file_loader'
require 'oci/errors'
require 'oci/global_context'
require 'oci/internal/internal'
require 'oci/regions'
require 'oci/regions_definitions'
require 'oci/response_headers'
require 'oci/response'
require 'oci/base_signer'
require 'oci/signer'
require 'oci/version'
require 'oci/waiter'
require 'oci/retry/retry'
require 'oci/object_storage/object_storage'
module OCI
   class << self
     attr_accessor :sdk_name

     # Defines the logger used for debugging for the OCI module.
     # For example, log to STDOUT by setting this to Logger.new(STDOUT).
     #
     # @return [Logger]
     attr_accessor :logger
   end
 end

OracleBMC = OCI

module Fluent::Plugin
  class OutOracleOCILogAnalytics < Output
    Fluent::Plugin.register_output('oci-logging-analytics', self)
    helpers :thread, :event_emitter

    MAX_FILES_PER_ZIP = 100
    METRICS_INVALID_REASON_MESSAGE = "MISSING_FIELD_MESSAGE"
    METRICS_INVALID_REASON_LOG_GROUP_ID = "MISSING_OCI_LA_LOG_GROUP_ID_FIELD"
    METRICS_INVALID_REASON_LOG_SOURCE_NAME = "MISSING_OCI_LA_LOG_SOURCE_NAME_FIELD"

    METRICS_SERVICE_ERROR_REASON_400 = "INVALID_PARAMETER"
    METRICS_SERVICE_ERROR_REASON_401 = "AUTHENTICATION_FAILED"
    METRICS_SERVICE_ERROR_REASON_404 = "AUTHORIZATION_FAILED"
    METRICS_SERVICE_ERROR_REASON_429 = "TOO_MANY_REQUESTES"
    METRICS_SERVICE_ERROR_REASON_500 = "INTERNAL_SERVER_ERROR"
    METRICS_SERVICE_ERROR_REASON_502 = "BAD_GATEWAY"
    METRICS_SERVICE_ERROR_REASON_503 = "SERVICE_UNAVAILABLE"
    METRICS_SERVICE_ERROR_REASON_504 = "GATEWAY_TIMEOUT"
    METRICS_SERVICE_ERROR_REASON_505 = "HTTP_VERSION_NOT_SUPPORTED"
    METRICS_SERVICE_ERROR_REASON_UNKNOWN = "UNKNOWN_ERROR"


    @@logger = nil
    @@loganalytics_client = nil
    @@prometheusMetrics = nil
    @@logger_config_errors = []
    @@worker_id = '0'
    @@encoded_messages_count = 0


    desc 'OCI Tenancy Namespace.'
    config_param :namespace,                    :string, :default => nil
    desc 'OCI config file location.'
    config_param :config_file_location,                    :string, :default => nil
    desc 'Name of the profile to be used.'
    config_param :profile_name,                    :string, :default => 'DEFAULT'
    desc 'OCI endpoint.'
    config_param :endpoint,                    :string, :default => nil
    desc 'AuthType to be used.'
    config_param :auth_type,                    :string, :default => 'InstancePrincipal'
    desc 'Enable local payload dump.'
    config_param :dump_zip_file,                    :bool, :default => false
    desc 'Payload zip File Location.'
    config_param :zip_file_location,                    :string, :default => nil
    desc 'The kubernetes_metadata_keys_mapping.'
    config_param :kubernetes_metadata_keys_mapping,                    :hash, :default => {"container_name":"Container","namespace_name":"Namespace","pod_name":"Pod","container_image":"Container Image Name","host":"Node"}
    desc 'opc-meta-properties'
    config_param :collection_source, :string, :default => Source::FLUENTD

    #****************************************************************
    desc 'The http proxy to be used.'
    config_param :http_proxy,                    :string, :default => nil
    desc 'The proxy_ip to be used.'
    config_param :proxy_ip,              :string, :default => nil
    desc 'The proxy_port to be used.'
    config_param :proxy_port,              :integer, :default => 80
    desc 'The proxy_username to be used.'
    config_param :proxy_username,              :string, :default => nil
    desc 'The proxy_password to be used.'
    config_param :proxy_password,              :string, :default => nil

    desc 'OCI Output plugin log location.'
    config_param :plugin_log_location,              :string, :default => nil
    desc 'OCI Output plugin log level.'
    config_param :plugin_log_level,              :string, :default => nil
    desc 'OCI Output plugin log rotation.'
    config_param :plugin_log_rotation,              :string, :default => nil
    desc 'OCI Output plugin log age.'
    config_param :plugin_log_age,              :string, :default => nil  # Deprecated
    desc 'The maximum log file size at which point the log file to be rotated.'
    config_param :plugin_log_file_size,              :string, :default => nil
    desc 'The number of archived/rotated log files to keep.'
    config_param :plugin_log_file_count,              :integer, :default => 10

    desc 'OCI Output plugin 4xx exception handling.' # Except '429'
    config_param :plugin_retry_on_4xx,              :bool, :default => false

    @@default_log_level = 'info'
    @@default_log_rotation = 'daily'
    @@validated_log_size = nil
    @@default_log_size = 1 * 1024 * 1024   # 1MB
    @@default_number_of_logs = 10

#************************************************************************
# following params are only for internal testing.

    desc 'Default is false. When true, prohibits HTTP requests to oci.'
    config_param :test_flag,        :bool,   :default => false
    desc 'Sets the environment. Default is prod.'
    config_param :environment,      :string, :default => "prod"
    desc 'Default log group'
    config_param :default_log_group,:string, :default => nil
#*************************************************************************
    # define default buffer section
    config_section :buffer do
      config_set_default :type, 'file'
      config_set_default :chunk_keys, ['oci_la_log_group_id']
      desc 'The number of threads of output plugins, which is used to write chunks in parallel.'
      config_set_default :flush_thread_count,  1
      desc 'The max size of each chunks: events will be written into chunks until the size of chunks become this size.'
      config_set_default :chunk_limit_size,    4 * 1024 * 1024  # 4MB
      desc 'The size limitation of this buffer plugin instance.'
      config_set_default :total_limit_size,    5 * (1024**3) # 5GB
      desc 'Flush interval'
      config_set_default :flush_interval,      30 # seconds
      desc 'The sleep interval of threads to wait next flush trial (when no chunks are waiting).'
      config_set_default :flush_thread_interval, 0.5
      desc 'The sleep interval seconds of threads between flushes when output plugin flushes waiting chunks next to next.'
      config_set_default :flush_thread_burst_interval, 0.05
      desc 'Seconds to wait before next retry to flush, or constant factor of exponential backoff.'
      config_set_default :retry_wait,          2 # seconds
      desc 'The maximum number of times to retry to flush while failing.'
      config_set_default :retry_max_times,     17
      desc 'The base number of exponential backoff for retries.'
      config_set_default :retry_exponential_backoff_base  ,  2
      desc 'retry_forever'
      config_set_default :retry_forever, true
    end

    def initialize
      super
    end

    def initialize_logger()
      begin
          filename = nil
          is_default_log_location = false
          if is_valid(@plugin_log_location)
            filename = @plugin_log_location[-1] == '/' ? @plugin_log_location : @plugin_log_location +'/'
          else
            @@logger = log
            return
          end
          if !is_valid_log_level(@plugin_log_level)
            @plugin_log_level = @@default_log_level
          end
          oci_fluent_output_plugin_log = nil
          if is_default_log_location
            oci_fluent_output_plugin_log = 'oci-logging-analytics.log'
          else
            oci_fluent_output_plugin_log = filename+'oci-logging-analytics.log'
          end
          logger_config = nil

          if is_valid_number_of_logs(@plugin_log_file_count) && is_valid_log_size(@plugin_log_file_size)
            # When customer provided valid log_file_count and log_file_size.
            # logger will rotate with max log_file_count with each file having max log_file_size.
            # Older logs purged automatically.
            @@logger = Logger.new(oci_fluent_output_plugin_log, @plugin_log_file_count, @@validated_log_size)
            logger_config = 'USER_CONFIG'
          elsif is_valid_log_rotation(@plugin_log_rotation)
            # When customer provided only log_rotation.
            # logger will create a new log based on log_rotation (new file everyday if the rotation is daily).
            # This will create too many logs over a period of time as log purging is not done.
            @@logger = Logger.new(oci_fluent_output_plugin_log, @plugin_log_rotation)
            logger_config = 'FALLBACK_CONFIG'
          else
            # When customer provided invalid log config, default config is considered.
            # logger will rotate with max default log_file_count with each file having max default log_file_size.
            # Older logs purged automatically.
            @@logger = Logger.new(oci_fluent_output_plugin_log, @@default_number_of_logs, @@default_log_size)
            logger_config = 'DEFAULT_CONFIG'
          end

          logger_set_level(@plugin_log_level)
          @@logger.info {"Initializing oci-logging-analytics plugin"}
          if is_default_log_location
            @@logger.info {"plugin_log_location is not specified. oci-logging-analytics.log will be generated under directory from where fluentd is executed."}
          end

          case logger_config
            when 'USER_CONFIG'
              @@logger.info {"Logger for oci-logging-analytics.log is initialized with config values log size: #{@plugin_log_file_size}, number of logs: #{@plugin_log_file_count}"}
            when 'FALLBACK_CONFIG'
              @@logger.info {"Logger for oci-logging-analytics.log is initialized with log rotation: #{@plugin_log_rotation}"}
            when 'DEFAULT_CONFIG'
              @@logger.info {"Logger for oci-logging-analytics.log is initialized with default config values log size: #{@@default_log_size}, number of logs: #{@@default_number_of_logs}"}
          end
          if @@logger_config_errors.length > 0
            @@logger_config_errors. each {|logger_config_error|
              @@logger.warn {"#{logger_config_error}"}
            }
          end
          if is_valid_log_age(@plugin_log_age)
            @@logger.warn {"'plugin_log_age' field is deprecated. Use 'plugin_log_file_size' and 'plugin_log_file_count' instead."}
          end
      rescue => ex
        @@logger = log
        @@logger.error {"Error while initializing logger:#{ex.inspect}"}
        @@logger.info {"Redirecting oci logging analytics logs to STDOUT"}
      end
    end

    def initialize_loganalytics_client()
        if is_valid(@config_file_location)
            @auth_type = "ConfigFile"
        end
        case @auth_type
          when "InstancePrincipal"
            instance_principals_signer = OCI::Auth::Signers::InstancePrincipalsSecurityTokenSigner.new
            if is_valid(@endpoint)
              @@loganalytics_client = OCI::LogAnalytics::LogAnalyticsClient.new(config: OCI::Config.new, endpoint: @endpoint, signer: instance_principals_signer)
              @@logger.info {"loganalytics_client initialised with endpoint: #{@endpoint}"}
            else
              @@loganalytics_client = OCI::LogAnalytics::LogAnalyticsClient.new(config: OCI::Config.new, signer: instance_principals_signer)
            end
          when "WorkloadIdentity"
            workload_identity_signer = OCI::Auth::Signers::oke_workload_resource_principal_signer
            if is_valid(@endpoint)
              @@loganalytics_client = OCI::LogAnalytics::LogAnalyticsClient.new(config: OCI::Config.new, endpoint: @endpoint, signer: workload_identity_signer)
              @@logger.info {"loganalytics_client initialised with endpoint: #{@endpoint}"}
            else
              @@loganalytics_client = OCI::LogAnalytics::LogAnalyticsClient.new(config: OCI::Config.new, signer: workload_identity_signer)
            end
          when "ConfigFile"
            my_config = OCI::ConfigFileLoader.load_config(config_file_location: @config_file_location, profile_name: @profile_name)
            if is_valid(@endpoint)
              @@loganalytics_client = OCI::LogAnalytics::LogAnalyticsClient.new(config: my_config, endpoint: @endpoint)
              @@logger.info {"loganalytics_client initialised with endpoint: #{@endpoint}"}
            else
              @@loganalytics_client = OCI::LogAnalytics::LogAnalyticsClient.new(config:my_config)
            end
          else
            raise Fluent::ConfigError, "Invalid authType @auth_type, authType must be either InstancePrincipal or ConfigFile."
            abort
        end

        if is_valid(@proxy_ip) && is_number(@proxy_port)
           if is_valid(@proxy_username)  && is_valid(@proxy_password)
              @@loganalytics_client.api_client.proxy_settings = OCI::ApiClientProxySettings.new(@proxy_ip, @proxy_port, @proxy_username, @proxy_password)
           else
              @@loganalytics_client.api_client.proxy_settings = OCI::ApiClientProxySettings.new(@proxy_ip, @proxy_port)
           end
        end

        rescue => ex
                @@logger.error {"Error occurred while initializing LogAnalytics Client:
                                  authType: #{@auth_type},
                                  errorMessage: #{ex}"}
    end

    def configure(conf)
      super
      @@prometheusMetrics = PrometheusMetrics.instance
      initialize_logger

      initialize_loganalytics_client
      #@@logger.error {"Error in config file : Buffer plugin must be of @type file."} unless buffer_config['@type'] == 'file'
      #raise Fluent::ConfigError, "Error in config file : Buffer plugin must be of @type file." unless buffer_config['@type'] == 'file'

      is_mandatory_fields_valid,invalid_field_name =  mandatory_field_validator
      if !is_mandatory_fields_valid
        @@logger.error {"Error in config file : invalid #{invalid_field_name}"}
        raise Fluent::ConfigError, "Error in config file : invalid #{invalid_field_name}"
      end

      # Get the chunk_limit_size from conf as it's not available in the buffer_config
      unless conf.elements(name: 'buffer').empty?
        buffer_conf = conf.elements(name: 'buffer').first
        chunk_limit_size_from_conf = buffer_conf['chunk_limit_size']
        unless chunk_limit_size_from_conf.nil? && buffer_config['@type'] != 'file'
          @@logger.debug "chunk limit size as per the configuration file is #{chunk_limit_size_from_conf}"
          case chunk_limit_size_from_conf.to_s
          when /([0-9]+)k/i
            chunk_limit_size_bytes = $~[1].to_i * 1024
          when /([0-9]+)m/i
            chunk_limit_size_bytes = $~[1].to_i * (1024 ** 2)
          when /([0-9]+)g/i
            chunk_limit_size_bytes = $~[1].to_i * (1024 ** 3)
          when /([0-9]+)t/i
            chunk_limit_size_bytes = $~[1].to_i * (1024 ** 4)
          #else
            #raise Fluent::ConfigError, "error parsing chunk_limit_size"
          end

          @@logger.debug "chunk limit size in bytes as per the configuration file is #{chunk_limit_size_bytes}"
          if chunk_limit_size_bytes != nil && !chunk_limit_size_bytes.between?(1048576, 4194304)
            raise Fluent::ConfigError, "chunk_limit_size must be between 1MB and 4MB"
          end
        end
      end

      if buffer_config.flush_interval < 10
        raise Fluent::ConfigError, "flush_interval must be greater than or equal to 10sec"
      end
      @mutex = Mutex.new
      @num_flush_threads = Float(buffer_config.flush_thread_count)
      max_chunk_lifespan = (buffer_config.retry_type == :exponential_backoff) ?
        buffer_config.retry_wait * buffer_config.retry_exponential_backoff_base**(buffer_config.retry_max_times+1) - 1 :
        buffer_config.retry_wait * buffer_config.retry_max_times
    end

    def get_or_parse_logSet(unparsed_logSet, record, record_hash, is_tag_exists)
          oci_la_log_set = nil
          parsed_logSet = nil
          if !is_valid(unparsed_logSet)
              return nil
          end
          if record_hash.has_key?("oci_la_log_set_ext_regex") && is_valid(record["oci_la_log_set_ext_regex"])
              parsed_logSet = unparsed_logSet.match(record["oci_la_log_set_ext_regex"])
              #*******************************************TO-DO**********************************************************
              # Based on the observed behaviour, below cases are handled. We need to revisit this section.
              # When trying to apply regex on a String and getting a matched substring, observed couple of scenarios.
              # For oci_la_log_set_ext_regex value = '.*\\\\/([^\\\\.]{1,40}).*' this returns an array with both input string and matched pattern
              # For oci_la_log_set_ext_regex value = '[ \\\\w-]+?(?=\\\\.)' this returns an array with only matched pattern
              # For few cases, String is returned instead of an array.
              #*******************************************End of TO-DO***************************************************
              if parsed_logSet!= nil    # Based on the regex pattern, match is returning different outputs for same input.
                if parsed_logSet.is_a? String
                  oci_la_log_set = parsed_logSet.encode("UTF-8")  # When matched String is returned instead of an array.
                elsif parsed_logSet.length > 1 #oci_la_log_set_ext_regex '.*\\\\/([^\\\\.]{1,40}).*' this returns an array with both input string and matched pattern
                  oci_la_log_set = parsed_logSet[1].encode("UTF-8")
                elsif parsed_logSet.length > 0 # oci_la_log_set_ext_regex '[ \\\\w-]+?(?=\\\\.)' this returns an array with only matched pattern
                  oci_la_log_set = parsed_logSet[0].encode("UTF-8") #Encoding to handle escape characters
                else
                  oci_la_log_set = nil
                end
              else
                oci_la_log_set = nil
                if is_tag_exists
                    @@logger.error {"Error occurred while parsing oci_la_log_set : #{unparsed_logSet} with oci_la_log_set_ext_regex : #{record["oci_la_log_set_ext_regex"]}. Default oci_la_log_set will be assigned to all the records with tag : #{record["tag"]}."}
                else
                    @@logger.error {"Error occurred while parsing oci_la_log_set : #{unparsed_logSet} with oci_la_log_set_ext_regex : #{record["oci_la_log_set_ext_regex"]}. Default oci_la_log_set will be assigned."}
                end
              end
          else
              oci_la_log_set = unparsed_logSet.force_encoding('UTF-8').encode("UTF-8")
          end
          return oci_la_log_set
          rescue => ex
               @@logger.error {"Error occurred while parsing oci_la_log_set : #{ex}. Default oci_la_log_set will be assigned."}
               return nil
        end

    def is_valid(field)
      if field.nil? || field.empty? then
        return false
      else
        return true
      end
    end

    def is_valid_log_rotation(log_rotation)
      if !is_valid(log_rotation)
        return false
      end
      case log_rotation.downcase
          when "daily"
            return true
          when "weekly"
            return true
          when "monthly"
            return true
          else
            @@logger_config_error << "Only 'daily'/'weekly'/'monthly' are supported for 'plugin_log_rotation'."
            return false
        end
    end

    def is_valid_log_age(param)
      if !is_valid(param)
        return false
      end
      case param.downcase
          when "daily"
            return true
          when "weekly"
            return true
          when "monthly"
            return true
          else
            return false
        end
    end

    def is_valid_log_level(param)
      if !is_valid(param)
        return false
      end
      case param.upcase
        when "DEBUG"
          return true
        when "INFO"
          return true
        when "WARN"
          return true
        when "ERROR"
          return true
        when "FATAL"
          return true
        when "UNKNOWN"
          return true
        else
          return false
      end
    end

    def logger_set_level(param)
      # DEBUG < INFO < WARN < ERROR < FATAL < UNKNOWN
      case @plugin_log_level.upcase
        when "DEBUG"
         @@logger.level = Logger::DEBUG
        when "INFO"
         @@logger.level = Logger::INFO
        when "WARN"
         @@logger.level = Logger::WARN
        when "ERROR"
         @@logger.level = Logger::ERROR
        when "FATAL"
         @@logger.level = Logger::FATAL
        when "UNKNOWN"
         @@logger.level = Logger::UNKNOWN
      end
    end

    def is_number(field)
      true if Integer(field) rescue false
    end

    def is_valid_log_size(log_size)
      if log_size != nil
        case log_size.to_s
          when /([0-9]+)k/i
            log_size = $~[1].to_i * 1024
          when /([0-9]+)m/i
            log_size = $~[1].to_i * (1024 ** 2)
          when /([0-9]+)g/i
            log_size = $~[1].to_i * (1024 ** 3)
          else
            @@logger_config_errors << "plugin_log_file_size must be greater than 1KB."
            return false
        end
        @@validated_log_size = log_size
        return true
      else
        return false
      end
    end

    def is_valid_number_of_logs(number_of_logs)
      if !is_number(number_of_logs) || number_of_logs < 1
        @@logger_config_errors << "plugin_log_file_count must be greater than zero"
        return false
      end
      return true
    end

    def get_valid_metadata(oci_la_metadata)
      if oci_la_metadata != nil
        if oci_la_metadata.is_a?(Hash)
            valid_metadata = Hash.new
            invalid_keys = []
            oci_la_metadata.each do |key, value|
              if value != nil && !value.is_a?(Hash) && !value.is_a?(Array)
                if key != nil && !key.is_a?(Hash) && !key.is_a?(Array)
                  valid_metadata[key] = value
                else
                  invalid_keys << key
                end
              else
                invalid_keys << key
              end
            end
            if invalid_keys.length > 0
              @@logger.warn {"Skipping the following oci_la_metadata/oci_la_global_metadata keys #{invalid_keys.compact.reject(&:empty?).join(',')} as the corresponding values are in invalid format."}
            end
            if valid_metadata.length > 0
              return valid_metadata
            else
              return nil
            end
        else
            @@logger.warn {"Ignoring 'oci_la_metadata'/'oci_la_global_metadata' provided in the record_transformer filter as only key-value pairs are supported."}
            return nil
        end
      else
        return nil
      end
    end

    def mandatory_field_validator
      begin
        if !is_valid(@namespace)
          return false,'namespace'
        elsif !is_valid(@config_file_location) && @auth_type == 'ConfigFile'
          return false,'config_file_location'
        elsif !is_valid(@profile_name)  && @auth_type == 'ConfigFile'
          return false,'profile_name'
        else
          return true,nil
        end
      end
    end

    def is_valid_record(record_hash,record)
      begin
         invalid_reason = nil
         if !record_hash.has_key?("message")
            invalid_reason = OutOracleOCILogAnalytics::METRICS_INVALID_REASON_MESSAGE
            if record_hash.has_key?("tag")
              @@logger.warn {"Invalid records associated with tag : #{record["tag"]}. 'message' field is not present in the record."}
            else
              @@logger.info {"InvalidRecord: #{record}"}
              @@logger.warn {"Invalid record. 'message' field is not present in the record."}
            end
            return false,invalid_reason
         elsif !record_hash.has_key?("oci_la_log_group_id") || !is_valid(record["oci_la_log_group_id"])
             invalid_reason = OutOracleOCILogAnalytics::METRICS_INVALID_REASON_LOG_GROUP_ID
             if record_hash.has_key?("tag")
               @@logger.warn {"Invalid records associated with tag : #{record["tag"]}.'oci_la_log_group_id' must not be empty.
                               Skipping all the records associated with the tag"}
             else
               @@logger.warn {"Invalid record.'oci_la_log_group_id' must not be empty"}
             end
             return false,invalid_reason
         elsif !record_hash.has_key?("oci_la_log_source_name") || !is_valid(record["oci_la_log_source_name"])
            invalid_reason = OutOracleOCILogAnalytics::METRICS_INVALID_REASON_LOG_SOURCE_NAME
            if record_hash.has_key?("tag")
              @@logger.warn {"Invalid records associated with tag : #{record["tag"]}.'oci_la_log_source_name' must not be empty.
                              Skipping all the records associated with the tag"}
            else
              @@logger.warn {"Invalid record.'oci_la_log_source_name' must not be empty"}
            end
            return false,invalid_reason
         else
            return true,invalid_reason
         end
      end
    end

    def flatten(kubernetes_metadata)
      kubernetes_metadata.each_with_object({}) do |(key, value), hash|
        hash[key] = value
        if value.is_a? Hash
          flatten(value).map do |hash_key, hash_value|
            hash["#{key}.#{hash_key}"] = hash_value
          end
        end
      end
    end

    def get_kubernetes_metadata(oci_la_metadata,record)
      if oci_la_metadata == nil
        oci_la_metadata = {}
      end
      kubernetes_metadata = flatten(record["kubernetes"])
      kubernetes_metadata.each do |key, value|
        if kubernetes_metadata_keys_mapping.has_key?(key)
           if !is_valid(oci_la_metadata[kubernetes_metadata_keys_mapping[key]])
              oci_la_metadata[kubernetes_metadata_keys_mapping[key]] = json_message_handler(key, value)
           end
        end
      end
      return oci_la_metadata
      rescue => ex
        @@logger.error {"Error occurred while getting kubernetes oci_la_metadata:
                          error message: #{ex}"}
        return oci_la_metadata
    end

    def json_message_handler(key, message)
        begin
            if !is_valid(message)
                return nil
            end
            if message.is_a?(Hash)
                return Yajl.dump(message) #JSON.generate(message)
            end
            return message
        rescue => ex
            @@logger.error {"Error occured while generating json for
                                field: #{key}
                                exception : #{ex}"}
            return nil
        end
    end

    def group_by_logGroupId(chunk)
      begin
         current  = Time.now
         current_f, current_s = current.to_f, current.strftime("%Y%m%dT%H%M%S%9NZ")
         records = []
         count = 0
         latency = 0
         records_per_tag = 0



         tag_metrics_set = Hash.new
         logGroup_labels_set = Hash.new

         invalid_tag_set = Set.new
         incoming_records_per_tag = Hash.new
         invalid_records_per_tag = Hash.new
         tags_per_logGroupId = Hash.new
         tag_logSet_map = Hash.new
         tag_metadata_map = Hash.new
         timezoneValuesByTag = Hash.new
         incoming_records = 0
         chunk.each do |time, record|
           incoming_records += 1
           metricsLabels = MetricsLabels.new
           if !record.nil?
              begin
                   record_hash = record.keys.map {|x| [x,true]}.to_h
                   if record_hash.has_key?("worker_id") && is_valid(record["worker_id"])
                        metricsLabels.worker_id = record["worker_id"]||= '0'
                        @@worker_id = record["worker_id"]||= '0'
                   end
                   is_tag_exists = false
                   if record_hash.has_key?("tag") && is_valid(record["tag"])
                     is_tag_exists = true
                     metricsLabels.tag = record["tag"]
                   end

                   if is_tag_exists && incoming_records_per_tag.has_key?(record["tag"])
                     incoming_records_per_tag[record["tag"]] += 1
                   elsif is_tag_exists
                     incoming_records_per_tag[record["tag"]] = 1
                   end
                  #For any given tag, if one record fails (mandatory fields validation) then all the records from that source will be ignored
                  if is_tag_exists && invalid_tag_set.include?(record["tag"])
                    invalid_records_per_tag[record["tag"]] += 1
                    next #This tag is already present in the invalid_tag_set, so ignoring the message.
                  end
                  #Setting tag/default value for oci_la_log_path, when not provided in config file.
                  if !record_hash.has_key?("oci_la_log_path") || !is_valid(record["oci_la_log_path"])
                       if is_tag_exists
                          record["oci_la_log_path"] = record["tag"]
                       else
                          record["oci_la_log_path"] = 'UNDEFINED'
                       end
                  end

                  #Extracting oci_la_log_set when oci_la_log_set_key and oci_la_log_set_ext_regex is provided.
                  #1) oci_la_log_set param is not provided in config file and above logic not executed.
                  #2) Valid oci_la_log_set_key + No oci_la_log_set_ext_regex
                    #a) Valid key available in record with oci_la_log_set_key corresponding value  (oci_la_log_set_key is a key in config file) --> oci_la_log_set
                    #b) No Valid key available in record with oci_la_log_set_key corresponding value --> nil
                  #3) Valid key available in record with oci_la_log_set_key corresponding value + Valid oci_la_log_set_ext_regex
                    #a) Parse success --> parsed oci_la_log_set
                    #b) Parse failure --> nil (as oci_la_log_set value)
                  #4) No oci_la_log_set_key --> do nothing --> nil

                  #Extracting oci_la_log_set when oci_la_log_set and oci_la_log_set_ext_regex is provided.
                  #1) Valid oci_la_log_set + No oci_la_log_set_ext_regex --> oci_la_log_set
                  #2) Valid oci_la_log_set + Valid oci_la_log_set_ext_regex
                    #a) Parse success --> parsed oci_la_log_set
                    #b) Parse failure --> nil (as oci_la_log_set value)
                  #3) No oci_la_log_set --> do nothing --> nil

                  unparsed_logSet = nil
                  processed_logSet = nil
                  if is_tag_exists && tag_logSet_map.has_key?(record["tag"])
                      record["oci_la_log_set"] = tag_logSet_map[record["tag"]]
                  else
                    if record_hash.has_key?("oci_la_log_set_key")
                        if is_valid(record["oci_la_log_set_key"]) && record_hash.has_key?(record["oci_la_log_set_key"])
                            if is_valid(record[record["oci_la_log_set_key"]])
                                unparsed_logSet = record[record["oci_la_log_set_key"]]
                                processed_logSet = get_or_parse_logSet(unparsed_logSet,record, record_hash,is_tag_exists)
                            end
                        end
                    end
                    if !is_valid(processed_logSet) && record_hash.has_key?("oci_la_log_set")
                        if is_valid(record["oci_la_log_set"])
                            unparsed_logSet = record["oci_la_log_set"]
                            processed_logSet = get_or_parse_logSet(unparsed_logSet,record, record_hash,is_tag_exists)
                        end
                    end
                    record["oci_la_log_set"] = processed_logSet
                    tag_logSet_map[record["tag"]] = processed_logSet
                  end
                  is_valid, metricsLabels.invalid_reason = is_valid_record(record_hash,record)

                  unless is_valid
                    if is_tag_exists
                      invalid_tag_set.add(record["tag"])
                      invalid_records_per_tag[record["tag"]] = 1
                    end
                    next
                  end

                  # metricsLabels.timezone = record["oci_la_timezone"]
                  metricsLabels.logGroupId = record["oci_la_log_group_id"]
                  metricsLabels.logSourceName = record["oci_la_log_source_name"]
                  if record["oci_la_log_set"] != nil
                      metricsLabels.logSet = record["oci_la_log_set"]
                  end
                  record["message"] = json_message_handler("message", record["message"])


                  #This will check for null or empty messages and only that record will be ignored.
                  if !is_valid(record["message"])
                      metricsLabels.invalid_reason = OutOracleOCILogAnalytics::METRICS_INVALID_REASON_MESSAGE
                      if is_tag_exists
                        if invalid_records_per_tag.has_key?(record["tag"])
                          invalid_records_per_tag[record["tag"]] += 1
                        else
                          invalid_records_per_tag[record["tag"]] = 1
                          @@logger.warn {"'message' field is empty or encoded, Skipping records associated with tag : #{record["tag"]}."}
                        end
                      else
                        @@logger.warn {"'message' field is empty or encoded, Skipping record."}
                      end
                      next
                  end

                  if record_hash.has_key?("kubernetes")
                    record["oci_la_metadata"] = get_kubernetes_metadata(record["oci_la_metadata"],record)
                  end

                  if tag_metadata_map.has_key?(record["tag"])
                    record["oci_la_metadata"] = tag_metadata_map[record["tag"]]
                  else
                    if record_hash.has_key?("oci_la_metadata")
                        record["oci_la_metadata"] = get_valid_metadata(record["oci_la_metadata"])
                        tags_per_logGroupId[record["tag"]] = record["oci_la_metadata"]
                    else
                        tags_per_logGroupId[record["tag"]] = nil
                    end
                  end

                  if is_tag_exists
                    if tags_per_logGroupId.has_key?(record["oci_la_log_group_id"])
                      if !tags_per_logGroupId[record["oci_la_log_group_id"]].include?(record["tag"])
                        tags_per_logGroupId[record["oci_la_log_group_id"]] += ", "+record["tag"]
                      end
                    else
                      tags_per_logGroupId[record["oci_la_log_group_id"]] = record["tag"]
                    end
                  end
                  # validating the timezone field
                   if !timezoneValuesByTag.has_key?(record["tag"])
                     begin
                       timezoneIdentifier = record["oci_la_timezone"]
                       unless is_valid(timezoneIdentifier)
                         record["oci_la_timezone"] = nil
                       else
                         isTimezoneExist = timezone_exist? timezoneIdentifier
                         unless isTimezoneExist
                           @@logger.warn { "Invalid timezone '#{timezoneIdentifier}', using default UTC." }
                           record["oci_la_timezone"] = "UTC"
                         end

                       end
                       timezoneValuesByTag[record["tag"]] = record["oci_la_timezone"]
                     end
                   else
                     record["oci_la_timezone"] = timezoneValuesByTag[record["tag"]]
                   end

                  records << record
              ensure
                 # To get chunk_time_to_receive metrics per tag, corresponding latency and total records are calculated
                 if tag_metrics_set.has_key?(record["tag"])
                      metricsLabels = tag_metrics_set[record["tag"]]
                      latency = metricsLabels.latency
                      records_per_tag = metricsLabels.records_per_tag
                 else
                      latency = 0
                      records_per_tag = 0
                 end
                 latency += (current_f - time)
                 records_per_tag += 1
                 metricsLabels.latency = latency
                 metricsLabels.records_per_tag = records_per_tag
                 tag_metrics_set[record["tag"]]  = metricsLabels
                 if record["oci_la_log_group_id"] != nil && !logGroup_labels_set.has_key?(record["oci_la_log_group_id"])
                     logGroup_labels_set[record["oci_la_log_group_id"]]  = metricsLabels
                 end
              end
           else
            @@logger.trace {"Record is nil, ignoring the record"}
           end
         end
         @@logger.debug {"records.length:#{records.length}"}

         tag_metrics_set.each do |tag,metricsLabels|
             latency_avg = (metricsLabels.latency / metricsLabels.records_per_tag).round(3)
             @@prometheusMetrics.chunk_time_to_receive.observe(latency_avg, labels: { worker_id: metricsLabels.worker_id, tag: tag})
         end

         lrpes_for_logGroupId = {}
         records.group_by{|record|
                      oci_la_log_group_id = record['oci_la_log_group_id']
                     (oci_la_log_group_id)
                      }.map {|oci_la_log_group_id, records_per_logGroupId|
                        lrpes_for_logGroupId[oci_la_log_group_id] = records_per_logGroupId
                      }
         rescue => ex
            @@logger.error {"Error occurred while grouping records by oci_la_log_group_id:#{ex.inspect}"}
      end
      return incoming_records_per_tag,invalid_records_per_tag,tag_metrics_set,logGroup_labels_set,tags_per_logGroupId,lrpes_for_logGroupId
    end
    # main entry point for FluentD's flush_threads, which get invoked
    # when a chunk is ready for flushing (see chunk limits and flush_intervals)
    def write(chunk)
      @@logger.info {"Received new chunk, started processing ..."}
      #@@prometheusMetrics.bytes_received.set(chunk.bytesize, labels: { tag: nil})
      begin
        # 1) Create an in-memory zipfile for the given FluentD chunk
        # 2) Synchronization has been removed. See EMCLAS-28675

        begin
          lrpes_for_logGroupId = {}
          incoming_records_per_tag,invalid_records_per_tag,tag_metrics_set,logGroup_labels_set,tags_per_logGroupId,lrpes_for_logGroupId = group_by_logGroupId(chunk)
          valid_message_per_tag = Hash.new
          logGroup_metrics_map = Hash.new
          metricsLabels_array = []

          incoming_records_per_tag.each do |key,value|
            dropped_messages = (invalid_records_per_tag.has_key?(key)) ? invalid_records_per_tag[key].to_i : 0
            valid_messages = value.to_i - dropped_messages
            valid_message_per_tag[key] = valid_messages

            metricsLabels = tag_metrics_set[key]
            if metricsLabels == nil
                metricsLabels = MetricsLabels.new
            end
            metricsLabels.records_valid = valid_messages
            # logGroup_metrics_map will have logGroupId as key and metricsLabels_array as value.
            # In a chunk we can have different logGroupIds but we are creating payloads based on logGroupId and that can internally have different logSourceName and tag data.
            # Using logGroup_metrics_map, for a given chunk, we can produce the metrics with proper logGroupId and its corresponding values.
            if metricsLabels.logGroupId != nil
               if logGroup_metrics_map.has_key?(metricsLabels.logGroupId)
                  metricsLabels_array = logGroup_metrics_map[metricsLabels.logGroupId]
               else
                  metricsLabels_array = []
               end
               metricsLabels_array.push(metricsLabels)
               logGroup_metrics_map[metricsLabels.logGroupId] = metricsLabels_array
            end

            @@prometheusMetrics.records_received.set(value.to_i, labels: { worker_id: metricsLabels.worker_id,
                                                                           tag: key,
                                                                           oci_la_log_group_id: metricsLabels.logGroupId,
                                                                           oci_la_log_source_name: metricsLabels.logSourceName,
                                                                           oci_la_log_set: metricsLabels.logSet})

            @@prometheusMetrics.records_invalid.set(dropped_messages, labels: { worker_id: metricsLabels.worker_id,
                                                                                 tag: key,
                                                                                 oci_la_log_group_id: metricsLabels.logGroupId,
                                                                                 oci_la_log_source_name: metricsLabels.logSourceName,
                                                                                 oci_la_log_set: metricsLabels.logSet,
                                                                                 reason: metricsLabels.invalid_reason})
            @@prometheusMetrics.records_valid.set(valid_messages, labels: { worker_id: metricsLabels.worker_id,
                                                                                tag: key,
                                                                                 oci_la_log_group_id: metricsLabels.logGroupId,
                                                                                 oci_la_log_source_name: metricsLabels.logSourceName,
                                                                                 oci_la_log_set: metricsLabels.logSet})

            if dropped_messages > 0
              @@logger.info {"Messages: #{value.to_i} \t Valid: #{valid_messages} \t Invalid: #{dropped_messages} \t tag:#{key}"}
            end
            @@logger.debug {"Messages: #{value.to_i} \t Valid: #{valid_messages} \t Invalid: #{dropped_messages} \t tag:#{key}"}
          end

          if lrpes_for_logGroupId != nil && lrpes_for_logGroupId.length > 0
            lrpes_for_logGroupId.each do |oci_la_log_group_id,records_per_logGroupId|
              begin
                tags = tags_per_logGroupId.key(oci_la_log_group_id)
                @@logger.info {"Generating payload with #{records_per_logGroupId.length}  records for oci_la_log_group_id: #{oci_la_log_group_id}"}
                zippedstream = nil
                oci_la_log_set = nil
                logSets_per_logGroupId_map = Hash.new

                metricsLabels_array = logGroup_metrics_map[oci_la_log_group_id]

                # Only MAX_FILES_PER_ZIP (100) files are allowed, which will be grouped and zipped.
                # Due to MAX_FILES_PER_ZIP constraint, for a oci_la_log_group_id, we can get more than one zip file and those many api calls will be made.
                logSets_per_logGroupId_map, oci_la_global_metadata = get_logSets_map_per_logGroupId(oci_la_log_group_id,records_per_logGroupId)
                 if logSets_per_logGroupId_map != nil
                    bytes_out = 0
                    records_out = 0
                    chunk_upload_time_taken = nil
                    chunk_upload_time_taken = Benchmark.measure {
                      logSets_per_logGroupId_map.each do |file_count,records_per_logSet_map|
                          zippedstream,number_of_records = get_zipped_stream(oci_la_log_group_id,oci_la_global_metadata,records_per_logSet_map)
                          if zippedstream != nil
                            zippedstream.rewind #reposition buffer pointer to the beginning
                            upload_to_oci(oci_la_log_group_id, number_of_records, zippedstream, metricsLabels_array)
                          end
                      end
                      }.real.round(3)
                      @@prometheusMetrics.chunk_time_to_upload.observe(chunk_upload_time_taken, labels: { worker_id: @@worker_id, oci_la_log_group_id: oci_la_log_group_id})

                 end
              ensure
                zippedstream&.close

              end
            end
          end
        end
      end
    end
    def timezone_exist?(tz)
      begin
        TZInfo::Timezone.get(tz)
        return true
      rescue TZInfo::InvalidTimezoneIdentifier
        return false
      end
    end

    # Each oci_la_log_set will correspond to a separate file in the zip
    # Only MAX_FILES_PER_ZIP files are allowed per zip.
    # Here we are grouping logSets so that if file_count reaches MAX_FILES_PER_ZIP, these files will be considered for a separate zip file.
    def get_logSets_map_per_logGroupId(oci_la_log_group_id,records_per_logGroupId)
        file_count = 0
        oci_la_global_metadata = nil
        is_oci_la_global_metadata_assigned = false
        oci_la_log_set = nil
        records_per_logSet_map = Hash.new
        logSets_per_logGroupId_map = Hash.new

        records_per_logGroupId.group_by { |record|
          if !is_oci_la_global_metadata_assigned
            record_hash = record.keys.map {|x| [x,true]}.to_h
            if record_hash.has_key?("oci_la_global_metadata")
              oci_la_global_metadata = record['oci_la_global_metadata']
            end
            is_oci_la_global_metadata_assigned = true
          end
          oci_la_log_set = record['oci_la_log_set']
          (oci_la_log_set)
        }.map { |oci_la_log_set, records_per_logSet|
            if file_count % OutOracleOCILogAnalytics::MAX_FILES_PER_ZIP == 0
                records_per_logSet_map = Hash.new
            end
            records_per_logSet_map[oci_la_log_set] = records_per_logSet
            file_count += 1
            if file_count % OutOracleOCILogAnalytics::MAX_FILES_PER_ZIP == 0
                logSets_per_logGroupId_map[file_count] = records_per_logSet_map
            end
        }
        logSets_per_logGroupId_map[file_count] = records_per_logSet_map
        return logSets_per_logGroupId_map,oci_la_global_metadata
        rescue => exc
                @@logger.error {"Error in mapping records to oci_la_log_set.
                                oci_la_log_group_id: #{oci_la_log_group_id},
                                error message:#{exc}"}
    end

    # takes a fluentD chunk and converts it to an in-memory zipfile, populating metrics hash provided
    # Any exception raised is passed into the metrics hash, to be re-thrown from write()
    def getCollectionSource(input)
      collections_src = []
      if !is_valid input
        collections_src.unshift("source:#{Source::FLUENTD}")
      else
        if input == Source::FLUENTD.to_s or input == Source::KUBERNETES_SOLUTION.to_s
          collections_src.unshift("source:#{input}")
        else
          # source not define ! using default source 'fluentd'
          collections_src.unshift("source:#{Source::FLUENTD}")
        end
      end
      collections_src
    end

    def get_zipped_stream(oci_la_log_group_id,oci_la_global_metadata,records_per_logSet_map)
       begin
        current,  = Time.now
        current_f, current_s = current.to_f, current.strftime("%Y%m%dT%H%M%S%9NZ")
        number_of_records = 0
        noOfFilesGenerated = 0
        zippedstream = Zip::OutputStream.write_buffer { |zos|
          records_per_logSet_map.each do |oci_la_log_set,records_per_logSet|
                lrpes_for_logEvents = records_per_logSet.group_by { |record| [
                  record['oci_la_metadata'],
                  record['oci_la_entity_id'],
                  record['oci_la_entity_type'],
                  record['oci_la_log_source_name'],
                  record['oci_la_log_path'],
                  record['oci_la_timezone']
                ]}.map { |lrpe_key, records_per_lrpe|
                  number_of_records += records_per_lrpe.length
                  LogEvents.new(lrpe_key, records_per_lrpe)
                }
                noOfFilesGenerated = noOfFilesGenerated +1
                if is_valid(oci_la_log_set) then
                  nextEntry = oci_la_log_group_id+ "_#{current_s}" +"_"+ noOfFilesGenerated.to_s + "_logSet=" + oci_la_log_set + ".json"     #oci_la_log_group_id + ".json"
                else
                  nextEntry = oci_la_log_group_id + "_#{current_s}" +"_"+ noOfFilesGenerated.to_s + ".json"
                end
                @@logger.debug {"Added entry #{nextEntry} for oci_la_log_set #{oci_la_log_set} into the zip."}
                zos.put_next_entry(nextEntry)
                logEventsJsonFinal = LogEventsJson.new(oci_la_global_metadata,lrpes_for_logEvents)
                zos.write Yajl.dump(logEventsJsonFinal.to_hash)
          end
        }
        zippedstream.rewind
        if @dump_zip_file
          save_zip_to_local(oci_la_log_group_id,zippedstream,current_s)
        end
        #zippedstream.rewind if records.length > 0  #reposition buffer pointer to the beginning
      rescue => exc
        @@logger.error {"Error in generating payload.
                        oci_la_log_group_id: #{oci_la_log_group_id},
                        error message:#{exc}"}
      end
      return zippedstream,number_of_records
    end

    def save_zip_to_local(oci_la_log_group_id, zippedstream, current_s)
      begin
        fileName = oci_la_log_group_id+"_"+current_s+'.zip'
        fileLocation = @zip_file_location+fileName
        file = File.open(fileLocation, "w")
        file.write(zippedstream.sysread)
        rescue => ex
                     @@logger.error {"Error occurred while saving zip file.
                                      oci_la_log_group_id: oci_la_log_group_id,
                                      fileLocation: @zip_file_location
                                      fileName: fileName
                                      error message: #{ex}"}
        ensure
          file.close unless file.nil?
      end
    end

    # upload zipped stream to oci
    def upload_to_oci(oci_la_log_group_id, number_of_records, zippedstream, metricsLabels_array)
      begin
        collection_src_prop = getCollectionSource @collection_source
        error_reason = nil
        error_code = nil
        opts = { payload_type: "ZIP", opc_meta_properties:collection_src_prop}

            response = @@loganalytics_client.upload_log_events_file(namespace_name=@namespace,
                                            logGroupId=oci_la_log_group_id ,
                                            uploadLogEventsFileDetails=zippedstream,
                                            opts)
        if !response.nil?  && response.status == 200 then
          headers = response.headers
          if metricsLabels_array != nil
              metricsLabels_array.each { |metricsLabels|
                @@prometheusMetrics.records_posted.set(metricsLabels.records_valid, labels: { worker_id: metricsLabels.worker_id,
                                                                                     tag: metricsLabels.tag,
                                                                                     oci_la_log_group_id: metricsLabels.logGroupId,
                                                                                     oci_la_log_source_name: metricsLabels.logSourceName,
                                                                                     oci_la_log_set: metricsLabels.logSet})
              }
          end

          #zippedstream.rewind #reposition buffer pointer to the beginning
          #zipfile = zippedstream&.sysread&.dup
          #bytes_out = zipfile&.length
          #@@prometheusMetrics.bytes_posted.set(bytes_out, labels: { oci_la_log_group_id: oci_la_log_group_id})

          @@logger.info {"The payload has been successfully uploaded to logAnalytics -
                         oci_la_log_group_id: #{oci_la_log_group_id},
                         ConsumedRecords: #{number_of_records},
                         Date: #{headers['date']},
                         Time: #{headers['timecreated']},
                         opc-request-id: #{headers['opc-request-id']},
                         opc-object-id: #{headers['opc-object-id']}"}
        end
        rescue OCI::Errors::ServiceError => serviceError
          error_code = serviceError.status_code
          case serviceError.status_code
               when 400
                 error_reason = OutOracleOCILogAnalytics::METRICS_SERVICE_ERROR_REASON_400
                 @@logger.error {"oci upload exception : Error while uploading the payload. Invalid/Incorrect/missing Parameter - opc-request-id:#{serviceError.request_id}"}
                 if plugin_retry_on_4xx
                    raise serviceError
                 end
               when 401
                 error_reason = OutOracleOCILogAnalytics::METRICS_SERVICE_ERROR_REASON_401
                 @@logger.error {"oci upload exception : Error while uploading the payload. Not Authenticated.
                                  opc-request-id:#{serviceError.request_id}
                                  message: #{serviceError.message}"}
                 if plugin_retry_on_4xx
                    raise serviceError
                 end
               when 404
                 error_reason = OutOracleOCILogAnalytics::METRICS_SERVICE_ERROR_REASON_404
                 @@logger.error {"oci upload exception : Error while uploading the payload. Authorization failed for given oci_la_log_group_id against given Tenancy Namespace.
                                  oci_la_log_group_id: #{oci_la_log_group_id}
                                  Namespace: #{@namespace}
                                  opc-request-id: #{serviceError.request_id}
                                  message: #{serviceError.message}"}
                 if plugin_retry_on_4xx
                    raise serviceError
                 end
               when 429
                 error_reason = OutOracleOCILogAnalytics::METRICS_SERVICE_ERROR_REASON_429
                 @@logger.error {"oci upload exception : Error while uploading the payload. Too Many Requests - opc-request-id:#{serviceError.request_id}"}
                 raise serviceError
               when 500
                 error_reason = OutOracleOCILogAnalytics::METRICS_SERVICE_ERROR_REASON_500
                 @@logger.error {"oci upload exception : Error while uploading the payload. Internal Server Error - opc-request-id:#{serviceError.request_id}"}
                 raise serviceError

               when 502
                  error_reason = OutOracleOCILogAnalytics::METRICS_SERVICE_ERROR_REASON_502
                  @@logger.error {"oci upload exception : Error while uploading the payload. Bad Gateway - opc-request-id:#{serviceError.request_id}"}
                  raise serviceError

               when 503
                  error_reason = OutOracleOCILogAnalytics::METRICS_SERVICE_ERROR_REASON_503
                  @@logger.error {"oci upload exception : Error while uploading the payload. Service unavailable - opc-request-id:#{serviceError.request_id}"}
                  raise serviceError

               when 504
                   error_reason = OutOracleOCILogAnalytics::METRICS_SERVICE_ERROR_REASON_504
                   @@logger.error {"oci upload exception : Error while uploading the payload. Gateway Timeout - opc-request-id:#{serviceError.request_id}"}
                   raise serviceError

               when 505
                   error_reason = OutOracleOCILogAnalytics::METRICS_SERVICE_ERROR_REASON_505
                   @@logger.error {"oci upload exception : Error while uploading the payload. HTTP Version Not Supported - opc-request-id:#{serviceError.request_id}"}
                   raise serviceError
               else
                 error_reason = OutOracleOCILogAnalytics::METRICS_SERVICE_ERROR_REASON_UNKNOWN
                 @@logger.error {"oci upload exception : Error while uploading the payload #{serviceError.message}"}
                 raise serviceError
             end
          rescue => ex
             error_reason = ex
             @@logger.error {"oci upload exception : Error while uploading the payload. #{ex}"}
          ensure
              if error_reason != nil && metricsLabels_array != nil
                  metricsLabels_array.each { |metricsLabels|
                    @@prometheusMetrics.records_error.set(metricsLabels.records_valid, labels: {worker_id: metricsLabels.worker_id,
                                                                                         tag: metricsLabels.tag,
                                                                                         oci_la_log_group_id: metricsLabels.logGroupId,
                                                                                         oci_la_log_source_name: metricsLabels.logSourceName,
                                                                                         oci_la_log_set: metricsLabels.logSet,
                                                                                         error_code: error_code,
                                                                                         reason: error_reason})
                  }
              end
      end
    end
  end
end
