# Octoryn Ruby SDK

Governed model access for Ruby 3.2 and later.

Install the public gem from RubyGems.org:

```bash
gem install octoryn-sdk -v 0.1.1
```

```ruby
client = Octoryn::Client.new(api_key: ENV.fetch("OCTORYN_API_KEY"))
result = client.generate_text(
  model: "openai/gpt-4.1-mini",
  prompt: "Explain this routing decision."
)

puts result.octoryn.evidence_hash
```

The SDK supports synchronous and asynchronous text generation, replayable SSE
streams, split tool calls, JSON Schema-validated Structured Outputs, normalized
errors, cancellation, replaceable transports and Octoryn governance metadata.
