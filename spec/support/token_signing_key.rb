require "open3"

# Deterministic ES-384 signing key for the token-auth specs.
#
# scripts/token_auth.py (shelled out to by TokenCreationService + IdentityController)
# reads its signing key from a FIXED path, /tmp/czid-private-key.pem. If that file is
# absent it falls back to AWS Secrets Manager -- which has no credentials under test, so
# the subprocess exits non-zero and TokenCreationService raises TokenCreationError.
#
# That key file used to be generated ONLY by a before hook in identity_controller_spec,
# so any other spec that mints a token (e.g. token_creation_service_spec) passed only when
# it happened to run in the same shard, after that spec. RSpec shards by FILE, so simply
# adding or removing a spec file elsewhere reshuffles the distribution and could break the
# token specs in an unrelated shard (a real, order-dependent flake).
#
# Generate the key once per RSpec process. Each shard is its own process, so before(:suite)
# runs once per shard and guarantees the key exists before any example -- independent of
# shard layout or example order.
RSpec.configure do |config|
  config.before(:suite) do
    key_path = "/tmp/czid-private-key.pem"
    _out, err, status = Open3.capture3(
      "openssl", "ecparam", "-name", "secp384r1", "-genkey", "-noout", "-out", key_path
    )
    raise "Could not generate #{key_path} for token-auth specs: #{err}" unless status.success?
  end
end
