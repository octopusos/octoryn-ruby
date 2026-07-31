# frozen_string_literal: true

module Octoryn
  # A lazy, cancellable, replayable stream of normalized Octoryn events.
  class TextStream
    include Enumerable

    def initialize(governance: nil, &producer)
      @governance = governance
      @producer = producer
      @events = []
      @source = nil
      @complete = false
      @result = nil
      @error = nil
      @cancelled = false
    end

    def each(&)
      return enum_for(:each) unless block_given?

      @events.each(&)
      return finish_replay if @complete

      consume_events(&)
      raise @error if @error
    end

    def result
      each { nil } unless @complete
      raise @error if @error

      @result || raise(Error, 'Octoryn stream has no final result')
    end

    def cancel
      @cancelled = true
      @error = Error.new('Octoryn stream cancelled')
      @complete = true
    end

    private

    def finish_replay
      raise @error if @error
    end

    def consume_events
      @source ||= consume
      loop do
        streamed = @source.next
        @events << streamed
        yield streamed
      end
    rescue StopIteration
      nil
    end

    def consume
      Enumerator.new do |events|
        state = stream_state
        started = false
        @producer.call do |chunk, metadata = nil|
          raise Error, 'Octoryn stream cancelled' if @cancelled

          if metadata
            @governance = metadata
            events << event('start', octoryn: @governance)
            started = true
            next
          end
          unless started
            events << event('start', octoryn: @governance)
            started = true
          end
          state[:buffer] << chunk
          parse_lines(state, events)
        end
        finalize_stream(state, events)
      rescue StandardError => e
        @error = e
        @complete = true
        events << event('error', octoryn: @governance, error: e)
      end
    end

    def stream_state
      {
        buffer: +'',
        data: [],
        text: +'',
        tools: {},
        usage: nil,
        finish_reason: nil,
        done: false
      }
    end

    def parse_lines(state, events)
      while (newline = state[:buffer].index("\n"))
        line = state[:buffer].slice!(0..newline).sub(/\r?\n\z/, '')
        if line.empty?
          process_event(state, events)
        elsif line.start_with?('data:')
          state[:data] << line.delete_prefix('data:').lstrip
        end
      end
    end

    def process_event(state, events)
      return if state[:data].empty?

      payload = state[:data].join("\n")
      state[:data].clear
      if payload == '[DONE]'
        state[:done] = true
        return
      end

      apply(JSON.parse(payload), state, events)
    end

    def apply(chunk, state, events)
      recognized = false
      if chunk['usage']
        state[:usage] = chunk['usage']
        events << event('usage', usage: state[:usage])
        recognized = true
      end
      Array(chunk['choices']).each do |choice|
        recognized = apply_delta(choice, state, events) || recognized
        state[:finish_reason] = choice['finish_reason'] if choice['finish_reason']
      end
      events << event('provider-event', provider_event: chunk) unless recognized
    end

    def apply_delta(choice, state, events)
      delta = choice.fetch('delta', {})
      content = delta['content']
      recognized = content.is_a?(String)
      append_text(content, state, events) if recognized
      reasoning = delta['reasoning'] || delta['reasoning_content']
      if reasoning.is_a?(String)
        events << event('reasoning-delta', text: reasoning)
        recognized = true
      end
      Array(delta['tool_calls']).each do |part|
        append_tool(part, state, events)
        recognized = true
      end
      recognized
    end

    def append_text(content, state, events)
      state[:text] << content
      events << event('text-delta', text: content)
    end

    def append_tool(part, state, events)
      index = part.fetch('index', 0)
      starting = !state[:tools].key?(index)
      tool = state[:tools][index] ||= {
        'id' => '',
        'type' => 'function',
        'name' => +'',
        'arguments' => +''
      }
      tool['id'] = part['id'] if part['id']
      tool['type'] = part['type'] if part['type']
      function = part.fetch('function', {})
      tool['name'] << function.fetch('name', '')
      tool['arguments'] << function.fetch('arguments', '')
      events << event('tool-call-start', provider_event: part) if starting
      events << event('tool-call-delta', provider_event: part)
    end

    def finalize_stream(state, events)
      process_trailing_data(state, events)
      raise Error, 'Octoryn stream ended before [DONE]' unless state[:done]

      calls = state[:tools].sort.map do |_index, tool|
        call = ToolCall.new(tool['id'], tool['name'], tool['arguments'], tool['type'])
        events << event('tool-call', tool_call: call)
        call
      end
      events << event(
        'finish',
        finish_reason: state[:finish_reason],
        octoryn: @governance
      )
      @result = TextResult.new(
        state[:text],
        calls,
        state[:finish_reason],
        state[:usage],
        @governance,
        nil
      )
      @complete = true
    end

    def process_trailing_data(state, events)
      unless state[:buffer].empty?
        line = state[:buffer].sub(/\r?\n\z/, '')
        state[:data] << line.delete_prefix('data:').lstrip if line.start_with?('data:')
      end
      process_event(state, events)
    end

    def event(type, **attributes)
      StreamEvent.new(
        type,
        attributes[:text],
        attributes[:tool_call],
        attributes[:usage],
        attributes[:finish_reason],
        attributes[:octoryn],
        attributes[:provider_event],
        attributes[:error]
      )
    end
  end
end
