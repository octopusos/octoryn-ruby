# frozen_string_literal: true

RSpec.describe Octoryn::Client do
  Response = Octoryn::Response

  class FakeTransport
    attr_reader :requests

    def initialize(*responses)
      @responses = responses
      @requests = []
    end

    def post(path, payload, stream: false)
      @requests << { path: path, payload: payload, stream: stream }
      response = @responses.shift or raise 'No fake response'
      if stream
        head = Response.new(response.status, response.headers, nil)
        yield head, nil
        Array(response.body).each { |chunk| yield head, chunk }
        head
      else
        response
      end
    end
  end

  def fixture(name)
    File.read(File.expand_path("../../sdk-conformance/v1/#{name}", __dir__))
  end

  def client(*responses)
    transport = FakeTransport.new(*responses)
    [
      described_class.new(api_key: 'test-key', transport: transport),
      transport
    ]
  end

  it 'normalizes text, tool calls, and governance evidence' do
    sdk, transport = client(Response.new(
                              200,
                              {
                                'x-octoryn-run-id' => 'run_ruby',
                                'x-octoryn-region' => 'au-sydney',
                                'x-octoryn-estimated-cost' => '0.001'
                              },
                              fixture('chat-completion.json')
                            ))

    result = sdk.generate_text(
      model: 'policy/frontier',
      prompt: 'Weather?',
      tools: [{
        'type' => 'function',
        'function' => {
          'name' => 'getWeather',
          'parameters' => {
            'type' => 'object',
            'properties' => { 'city' => { 'type' => 'string' } }
          }
        }
      }]
    )

    expect(result.text).to eq('Governed answer')
    expect(result.tool_calls.first.decode_input).to eq('city' => 'Sydney')
    expect(result.octoryn.run_id).to eq('run_ruby')
    expect(result.octoryn.region).to eq('au-sydney')
    expect(result.octoryn.estimated_cost).to eq(0.001)
    expect(transport.requests.first[:payload]['model']).to eq('policy/frontier')
  end

  it 'validates structured output against JSON Schema' do
    body = {
      'choices' => [{
        'message' => {
          'role' => 'assistant',
          'content' => '{"risk":"low","score":7}'
        },
        'finish_reason' => 'stop'
      }]
    }
    sdk, transport = client(Response.new(200, {}, JSON.generate(body)))

    result = sdk.generate_object(
      model: 'policy/risk',
      prompt: 'Assess',
      schema_name: 'risk_assessment',
      schema: {
        'type' => 'object',
        'properties' => {
          'risk' => { 'type' => 'string' },
          'score' => { 'type' => 'number' }
        },
        'required' => %w[risk score],
        'additionalProperties' => false
      }
    )

    expect(result.object).to eq('risk' => 'low', 'score' => 7)
    format = transport.requests.first[:payload]['response_format']
    expect(format['type']).to eq('json_schema')
    expect(format['json_schema']['strict']).to be(true)
  end

  it 'preserves raw structured output when validation fails' do
    body = {
      'choices' => [{
        'message' => { 'role' => 'assistant', 'content' => '{"risk":42}' },
        'finish_reason' => 'stop'
      }]
    }
    sdk, = client(Response.new(200, {}, JSON.generate(body)))

    expect do
      sdk.generate_object(
        model: 'policy/risk',
        prompt: 'Assess',
        schema: {
          'type' => 'object',
          'properties' => { 'risk' => { 'type' => 'string' } },
          'required' => ['risk']
        }
      )
    end.to raise_error(Octoryn::StructuredOutputError) { |error|
      expect(error.raw_output).to eq('{"risk":42}')
      expect(error.validation_errors).not_to be_empty
    }
  end

  it 'replays stream events and assembles split tool calls' do
    chunks = fixture('chat-stream.sse').scan(/.{1,37}/m)
    sdk, = client(Response.new(
                    200,
                    { 'x-octoryn-upstream' => 'anthropic' },
                    chunks
                  ))

    stream = sdk.stream_text(model: 'policy/frontier', prompt: 'Weather?')
    first = stream.to_a
    second = stream.to_a
    result = stream.result

    expect(second).to eq(first)
    expect(result.text).to eq('Octoryn')
    expect(result.tool_calls.first.decode_input).to eq('city' => 'Sydney')
    expect(result.octoryn.upstream).to eq('anthropic')
    expect(first.map(&:type)).to include('tool-call-start', 'tool-call-delta')
  end

  it 'maps API errors' do
    sdk, = client(Response.new(
                    429,
                    { 'retry-after' => '2' },
                    JSON.generate(
                      'error' => {
                        'code' => 'quota_exceeded',
                        'message' => 'budget exhausted'
                      }
                    )
                  ))

    expect do
      sdk.generate_text(model: 'policy/frontier', prompt: 'hello')
    end.to raise_error(Octoryn::APIError) { |error|
      expect(error.code).to eq('quota_exceeded')
      expect(error.retry_after).to eq(2)
    }
  end

  it 'cancels streams before transport execution' do
    sdk, = client(Response.new(200, {}, [fixture('chat-stream.sse')]))
    stream = sdk.stream_text(model: 'policy/frontier', prompt: 'hello')
    stream.cancel

    expect { stream.result }.to raise_error(Octoryn::Error, /cancelled/)
  end

  it 'offers an asynchronous text entry point' do
    body = {
      'choices' => [{
        'message' => { 'role' => 'assistant', 'content' => 'async' },
        'finish_reason' => 'stop'
      }]
    }
    sdk, = client(Response.new(200, {}, JSON.generate(body)))

    expect(
      sdk.generate_text_async(
        model: 'policy/frontier',
        prompt: 'hello'
      ).value.text
    ).to eq('async')
  end
end
