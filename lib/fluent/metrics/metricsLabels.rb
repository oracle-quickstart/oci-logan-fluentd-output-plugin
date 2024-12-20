## Copyright (c) 2021, 2024  Oracle and/or its affiliates.
## The Universal Permissive License (UPL), Version 1.0 as shown at https://oss.oracle.com/licenses/upl/

class MetricsLabels
  attr_accessor :worker_id, :tag, :logGroupId, :logSourceName, :logSet, :invalid_reason, :records_valid, :records_per_tag, :latency,:timezone
  def initialize
      @worker_id = nil
      @tag = nil
      @logGroupId = nil
      @logSourceName = nil
      @logSet = nil
      @invalid_reason = nil
      @records_valid = 0
      @records_per_tag = 0
      @latency = 0
      @timezone = nil
    end
end
