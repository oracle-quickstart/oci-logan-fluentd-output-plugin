## Copyright (c) 2021, 2024  Oracle and/or its affiliates.
## The Universal Permissive License (UPL), Version 1.0 as shown at https://oss.oracle.com/licenses/upl/

require_relative './logEvents'

class LogEventsJson
  attr_accessor :metadata, :LogEvents
  def initialize(metadata,logEvents)
    if metadata!= nil || metadata != 'null'
      @metadata = metadata
    end
    @LogEvents = logEvents
  end

  def to_hash
    {
      metadata: @metadata,
      logEvents: @LogEvents.map do |le|
        le.to_hash
      end
    }.compact
  end

end
