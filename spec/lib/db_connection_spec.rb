# frozen_string_literal: true

require "rails_helper"

# Specs for the #496 DB self-heal helper. Connection loss is simulated by raising
# the AR connection-loss exceptions; a live test DB connection covers the happy path.
RSpec.describe DbConnection do
  describe ".verify!" do
    it "returns true when the connection is alive" do
      expect(described_class.verify!).to be(true)
    end

    it "forces a reconnect and never raises when verify! fails" do
      conn = ActiveRecord::Base.connection
      allow(conn).to receive(:verify!).and_raise(ActiveRecord::ConnectionNotEstablished)
      expect(conn).to receive(:reconnect!)
      expect { described_class.verify! }.not_to raise_error
    end

    it "returns false when the connection cannot be revived" do
      conn = ActiveRecord::Base.connection
      allow(conn).to receive(:verify!).and_raise(ActiveRecord::ConnectionNotEstablished)
      allow(conn).to receive(:reconnect!).and_raise(StandardError, "still dead")
      expect(described_class.verify!).to be(false)
    end
  end

  describe ".with_reconnect" do
    it "returns the block value on the happy path without reconnecting" do
      expect(ActiveRecord::Base.connection).not_to receive(:reconnect!)
      expect(described_class.with_reconnect("ctx") { 123 }).to eq(123)
    end

    it "reconnects and retries on a connection-loss error, then succeeds" do
      allow(ActiveRecord::Base.connection).to receive(:reconnect!)
      calls = 0
      result = described_class.with_reconnect("ctx", max_retries: 2) do
        calls += 1
        raise ActiveRecord::StatementInvalid, "server has gone away" if calls == 1

        "ok"
      end
      expect(result).to eq("ok")
      expect(calls).to eq(2)
      expect(ActiveRecord::Base.connection).to have_received(:reconnect!).once
    end

    it "gives up and re-raises after exhausting max_retries" do
      allow(ActiveRecord::Base.connection).to receive(:reconnect!)
      calls = 0
      expect do
        described_class.with_reconnect("ctx", max_retries: 2) do
          calls += 1
          raise ActiveRecord::ConnectionNotEstablished, "gone"
        end
      end.to raise_error(ActiveRecord::ConnectionNotEstablished)
      # initial attempt + 2 retries
      expect(calls).to eq(3)
    end

    it "does not swallow non-connection errors" do
      expect(ActiveRecord::Base.connection).not_to receive(:reconnect!)
      expect do
        described_class.with_reconnect("ctx") { raise ArgumentError, "bad" }
      end.to raise_error(ArgumentError)
    end
  end
end
