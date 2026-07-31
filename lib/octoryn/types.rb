# frozen_string_literal: true

module Octoryn
  GovernanceMetadata = Data.define(
    :run_id,
    :upstream,
    :byok,
    :region,
    :route,
    :policy_decision,
    :evidence_hash,
    :estimated_cost
  )

  ToolCall = Data.define(:id, :name, :arguments, :type) do
    def decode_input
      value = JSON.parse(arguments)
      raise JSON::ParserError, 'tool arguments must be an object' unless value.is_a?(Hash)

      value
    end
  end

  TextResult = Data.define(
    :text,
    :tool_calls,
    :finish_reason,
    :usage,
    :octoryn,
    :response
  )

  ObjectResult = Data.define(:object, :result)

  StreamEvent = Data.define(
    :type,
    :text,
    :tool_call,
    :usage,
    :finish_reason,
    :octoryn,
    :provider_event,
    :error
  )
end
