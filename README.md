# Octoryn Ruby SDK

Governed model access for Ruby 3.2 and later.

Until `octoryn-sdk` is available from RubyGems.org, install the public release
artifact directly:

```bash
curl -fLO \
  https://github.com/octopusos/octoryn-ruby/releases/download/v0.1.1/octoryn-sdk-0.1.1.gem
gem install ./octoryn-sdk-0.1.1.gem
```

```ruby
client = Octoryn::Client.new(api_key: ENV.fetch("OCTORYN_API_KEY"))
result = client.generate_text(
  model: "policy/au-enterprise",
  prompt: "Explain this routing decision."
)

puts result.octoryn.evidence_hash
```

The SDK supports synchronous and asynchronous text generation, replayable SSE
streams, split tool calls, JSON Schema-validated Structured Outputs, normalized
errors, cancellation, replaceable transports and Octoryn governance metadata.
