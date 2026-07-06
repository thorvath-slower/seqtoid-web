# frozen_string_literal: true

require "rails_helper"

# JsonWebToken.jwks_hash is the Auth0 JWKS fetch on the auth hot path. As part of
# #467 the bare Net::HTTP.get was wrapped in a shared circuit breaker + bounded
# timeouts + transient retries (HttpResilience). These specs cover that fetch path
# (parsing, caching, and the resilience wrapping) without hitting Auth0 -- the
# JWKS endpoint is stubbed with WebMock and a real self-signed cert so the x5c
# -> public_key parsing exercises the actual OpenSSL code.
RSpec.describe JsonWebToken do
  # Build a real RSA cert and its Auth0-style JWKS JSON so parsing is genuine.
  let(:rsa_key) { OpenSSL::PKey::RSA.new(2048) }
  let(:kid) { "test-kid-1" }
  let(:certificate) do
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.subject = OpenSSL::X509::Name.parse("/CN=test")
    cert.issuer = cert.subject
    cert.public_key = rsa_key.public_key
    cert.not_before = Time.now
    cert.not_after = Time.now + 3600
    cert.sign(rsa_key, OpenSSL::Digest.new("SHA256"))
    cert
  end
  let(:x5c) { Base64.strict_encode64(certificate.to_der) }
  let(:jwks_body) do
    { keys: [{ kid: kid, x5c: [x5c] }] }.to_json
  end

  before do
    described_class.instance_variable_set(:@jwks_hash_cache, {})
    HttpResilience.reset!
  end

  describe ".jwks_hash" do
    it "fetches, parses, and returns a kid -> public_key map" do
      stub_request(:get, JsonWebToken::JWT_JWKS_KEYS_URL).to_return(status: 200, body: jwks_body)

      result = described_class.jwks_hash
      expect(result).to have_key(kid)
      expect(result[kid]).to be_a(OpenSSL::PKey::RSA)
      expect(result[kid].public?).to be(true)
    end

    it "routes the fetch through the HttpResilience :auth0_jwks circuit breaker" do
      breaker = HttpResilience.breaker(:auth0_jwks)
      expect(HttpResilience).to receive(:breaker).with(:auth0_jwks).and_return(breaker)
      expect(breaker).to receive(:run).and_call_original
      stub_request(:get, JsonWebToken::JWT_JWKS_KEYS_URL).to_return(status: 200, body: jwks_body)

      described_class.jwks_hash
    end

    it "retries a transient 5xx from Auth0 and then succeeds (resilience wrapping)" do
      stub_request(:get, JsonWebToken::JWT_JWKS_KEYS_URL)
        .to_return({ status: 503, body: "" }, { status: 200, body: jwks_body })
      # Avoid real backoff sleeps: HttpResilience.get uses sleep internally, keep it fast.
      allow_any_instance_of(Object).to receive(:sleep)

      result = described_class.jwks_hash
      expect(result).to have_key(kid)
    end

    it "surfaces (does not swallow) an exhausted-retry failure so the caller can 401" do
      stub_request(:get, JsonWebToken::JWT_JWKS_KEYS_URL).to_return(status: 500, body: "")
      allow_any_instance_of(Object).to receive(:sleep)

      expect { described_class.jwks_hash }.to raise_error(HttpResilience::TransientHttpError)
    end
  end

  describe ".cached_jwks" do
    it "returns a cached key without refetching when the kid is present" do
      described_class.instance_variable_set(:@jwks_hash_cache, { kid => :cached_key })
      # No WebMock stub registered -> if it tried to fetch, WebMock would raise.
      expect(described_class.cached_jwks(kid)).to eq(:cached_key)
    end

    it "refreshes from Auth0 when the kid is missing from the cache" do
      stub_request(:get, JsonWebToken::JWT_JWKS_KEYS_URL).to_return(status: 200, body: jwks_body)
      expect(described_class.cached_jwks(kid)).to be_a(OpenSSL::PKey::RSA)
    end
  end
end
