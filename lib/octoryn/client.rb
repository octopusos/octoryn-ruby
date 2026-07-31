# frozen_string_literal: true

require 'json'
require 'json_schemer'

module Octoryn
  # High-level governed client for text, tools, streaming, and JSON Schema output.
  class Client
    def initialize(api_key:, base_url: 'https://api.octoryn.dev/v1/',
                   transport: nil)
      raise ArgumentError, 'Octoryn API key is required' if api_key.to_s.strip.empty?

      @transport = transport || NetHTTPTransport.new(
        base_url: base_url,
        api_key: api_key
      )
    end

    def generate_text(**options)
      response = request(build_request(options, stream: false))
      normalize(JSON.parse(response.body), governance(response))
    end

    def generate_text_async(**options)
      Thread.new { generate_text(**options) }
    end

    def generate_object(schema:, schema_name: 'response',
                        schema_description: nil, **options)
      payload = build_request(options, stream: false)
      payload['response_format'] = {
        'type' => 'json_schema',
        'json_schema' => {
          'name' => schema_name,
          'description' => schema_description,
          'strict' => true,
          'schema' => schema
        }
      }
      response = request(payload)
      result = normalize(JSON.parse(response.body), governance(response))
      object = parse_structured(result.text)
      errors = JSONSchemer.schema(schema).validate(object).to_a
      unless errors.empty?
        raise StructuredOutputError.new(
          'Octoryn structured output does not match the JSON Schema',
          raw_output: result.text,
          validation_errors: errors
        )
      end
      ObjectResult.new(object, result)
    end

    def stream_text(**options)
      payload = build_request(options, stream: true)
      producer = proc do |&on_chunk|
        response = @transport.post('chat/completions', payload, stream: true) do |head, chunk|
          if chunk.nil?
            ensure_success!(head)
            on_chunk.call(nil, governance(head))
          else
            on_chunk.call(chunk, nil)
          end
        end
        ensure_success!(response)
      end
      TextStream.new(&producer)
    end

    private

    def build_request(options, stream:)
      model = options[:model]
      raise ArgumentError, 'model is required' if model.to_s.strip.empty?

      has_prompt = options.key?(:prompt)
      has_messages = options.key?(:messages)
      raise ArgumentError, 'pass exactly one of prompt or messages' if has_prompt == has_messages

      messages = []
      messages << { 'role' => 'system', 'content' => options[:system] } if options[:system]
      if has_prompt
        messages << { 'role' => 'user', 'content' => options[:prompt] }
      else
        messages.concat(Array(options[:messages]))
      end
      payload = { 'model' => model, 'messages' => messages, 'stream' => stream }
      {
        temperature: 'temperature',
        top_p: 'top_p',
        max_output_tokens: 'max_tokens',
        tools: 'tools',
        tool_choice: 'tool_choice',
        metadata: 'metadata'
      }.each do |input, output|
        payload[output] = options[input] if options.key?(input)
      end
      payload
    end

    def request(payload)
      response = @transport.post('chat/completions', payload, stream: false)
      ensure_success!(response)
      response
    end

    def normalize(response, metadata)
      choice = Array(response['choices']).first
      raise Error, 'Octoryn response contained no choices' unless choice

      message = choice.fetch('message', {})
      TextResult.new(
        text_content(message['content']),
        Array(message['tool_calls']).filter_map { |call| normalize_tool(call) },
        choice['finish_reason'],
        response['usage'],
        metadata,
        response
      )
    end

    def normalize_tool(call)
      function = call['function']
      return unless function.is_a?(Hash)

      ToolCall.new(
        call.fetch('id', ''),
        function.fetch('name', ''),
        function.fetch('arguments', '{}'),
        call.fetch('type', 'function')
      )
    end

    def text_content(content)
      return content if content.is_a?(String)
      return '' unless content.is_a?(Array)

      content.filter_map do |part|
        part['text'] if part.is_a?(Hash) && part['type'] == 'text'
      end.join
    end

    def governance(response)
      header = ->(name) { response.headers[name.downcase] || response.headers[name] }
      cost = header.call('x-octoryn-estimated-cost')
      GovernanceMetadata.new(
        header.call('x-octoryn-run-id'),
        header.call('x-octoryn-upstream'),
        header.call('x-octoryn-byok'),
        header.call('x-octoryn-region'),
        header.call('x-octoryn-route'),
        header.call('x-octoryn-policy-decision'),
        header.call('x-octoryn-evidence-hash'),
        cost&.to_f
      )
    end

    def ensure_success!(response)
      return if response.status.between?(200, 299)

      body = response.body ? JSON.parse(response.body) : {}
      error = body.fetch('error', {})
      raise APIError.new(
        status: response.status,
        message: error.fetch('message', 'Octoryn request failed'),
        code: error['code'],
        error_type: error['type'],
        request_id: response.headers['x-request-id'],
        retry_after: response.headers['retry-after']&.to_i
      )
    rescue JSON::ParserError
      raise APIError.new(status: response.status, message: 'Octoryn request failed')
    end

    def parse_structured(raw)
      JSON.parse(raw)
    rescue JSON::ParserError => e
      raise StructuredOutputError.new(
        'Octoryn structured output is not valid JSON',
        raw_output: raw,
        validation_errors: []
      ), cause: e
    end
  end
end
