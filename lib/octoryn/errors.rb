# frozen_string_literal: true

module Octoryn
  class Error < StandardError; end

  # A normalized non-success response from the Octoryn API.
  class APIError < Error
    attr_reader :status, :code, :error_type, :request_id, :retry_after

    def initialize(status:, message:, code: nil, error_type: nil,
                   request_id: nil, retry_after: nil)
      super(message)
      @status = status
      @code = code
      @error_type = error_type
      @request_id = request_id
      @retry_after = retry_after
    end
  end

  # Raised when structured output is invalid JSON or violates its schema.
  class StructuredOutputError < Error
    attr_reader :raw_output, :validation_errors

    def initialize(message, raw_output:, validation_errors: [])
      super(message)
      @raw_output = raw_output
      @validation_errors = validation_errors
    end
  end
end
