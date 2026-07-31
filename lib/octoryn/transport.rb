# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

module Octoryn
  Response = Data.define(:status, :headers, :body)

  # Standard-library HTTP transport with incremental response-body streaming.
  class NetHTTPTransport
    def initialize(base_url:, api_key:, open_timeout: 30, read_timeout: 600)
      @base_url = base_url.end_with?('/') ? base_url : "#{base_url}/"
      @api_key = api_key
      @open_timeout = open_timeout
      @read_timeout = read_timeout
    end

    def post(path, payload, stream: false, &block)
      uri = URI.join(@base_url, path)
      request = Net::HTTP::Post.new(uri)
      request['Authorization'] = "Bearer #{@api_key}"
      request['Content-Type'] = 'application/json'
      request['Accept'] = stream ? 'text/event-stream' : 'application/json'
      request['User-Agent'] = 'octoryn-ruby/0.1.0'
      request['X-Octoryn-Sdk'] = 'ruby/0.1.0'
      request.body = JSON.generate(payload)

      Net::HTTP.start(
        uri.hostname,
        uri.port,
        use_ssl: uri.scheme == 'https',
        open_timeout: @open_timeout,
        read_timeout: @read_timeout
      ) do |http|
        if stream
          stream_response(http, request, &block)
        else
          response = http.request(request)
          Response.new(response.code.to_i, headers(response), response.body)
        end
      end
    end

    private

    def stream_response(http, request)
      final = nil
      http.request(request) do |response|
        final = Response.new(response.code.to_i, headers(response), nil)
        yield final, nil
        response.read_body { |chunk| yield final, chunk }
      end
      final
    end

    def headers(response)
      response.each_header.to_h
    end
  end
end
