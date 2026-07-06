require "rails_helper"

RSpec.describe MetricUtil do
  describe "#a_test?" do
    it "returns true when running in RSpec" do
      expect(MetricUtil.send(:a_test?)).to eq(true)
    end

    it "returns false when env is overridden" do
      temp = Rails.env
      begin
        Rails.env = "asdf"
        expect(MetricUtil.send(:a_test?)).to eq(false)
      rescue StandardError => err
        raise err
      ensure
        Rails.env = temp
      end
    end

    it "returns true for a 'Rails Testing' user-agent even when env is not test" do
      temp = Rails.env
      begin
        Rails.env = "asdf"
        request = double("request", user_agent: "Rails Testing")
        expect(MetricUtil.send(:a_test?, request)).to eq(true)
      ensure
        Rails.env = temp
      end
    end

    it "returns false for a non-testing user-agent when env is not test" do
      temp = Rails.env
      begin
        Rails.env = "asdf"
        request = double("request", user_agent: "Mozilla/5.0")
        expect(MetricUtil.send(:a_test?, request)).to eq(false)
      ensure
        Rails.env = temp
      end
    end
  end

  describe "#context_for_segment" do
    it "shapes the Segment context hash from the request" do
      request = double(
        "request",
        fullpath: "/samples/1?foo=bar",
        referer: "https://ref.example.com",
        original_url: "https://app.example.com/samples/1?foo=bar",
        user_agent: "UA/1.0",
        remote_ip: "10.0.0.1"
      )

      context = MetricUtil.send(:context_for_segment, request)

      expect(context[:page][:path]).to eq("/samples/1")
      expect(context[:page][:search]).to eq("foo=bar")
      expect(context[:page][:referrer]).to eq("https://ref.example.com")
      expect(context[:page][:url]).to eq("https://app.example.com/samples/1?foo=bar")
      expect(context[:userAgent]).to eq("UA/1.0")
      expect(context[:ip]).to eq("10.0.0.1")
    end
  end

  describe "#log_analytics_event" do
    let(:user) { create(:user) }

    it "no-ops in the test environment even when analytics is configured" do
      analytics = double("analytics")
      stub_const("MetricUtil::SEGMENT_ANALYTICS", analytics)
      expect(analytics).not_to receive(:identify)
      expect(analytics).not_to receive(:track)

      # a_test? is true under RSpec, so the guard short-circuits.
      MetricUtil.log_analytics_event("some_event", user, { a: 1 })
    end

    it "identifies and tracks when analytics is present and the request is not a test" do
      analytics = double("analytics")
      stub_const("MetricUtil::SEGMENT_ANALYTICS", analytics)
      request = double(
        "request",
        user_agent: "Mozilla/5.0",
        fullpath: "/x?y=z",
        referer: nil,
        original_url: "https://app/x?y=z",
        remote_ip: "1.2.3.4"
      )

      expect(analytics).to receive(:identify).with(
        hash_including(user_id: user.id, traits: user.traits_for_analytics)
      )
      expect(analytics).to receive(:track).with(
        hash_including(event: "upload_started", user_id: user.id)
      )

      MetricUtil.log_analytics_event("upload_started", user, { foo: "bar" }, request)
    end

    it "uses user_id 0 and skips identify when no user is given" do
      analytics = double("analytics")
      stub_const("MetricUtil::SEGMENT_ANALYTICS", analytics)
      request = double(
        "request",
        user_agent: "Mozilla/5.0",
        fullpath: "/x",
        referer: nil,
        original_url: "https://app/x",
        remote_ip: "1.2.3.4"
      )

      expect(analytics).not_to receive(:identify)
      expect(analytics).to receive(:track).with(hash_including(user_id: 0))

      MetricUtil.log_analytics_event("anon_event", nil, {}, request)
    end

    it "swallows errors and logs them instead of raising" do
      analytics = double("analytics")
      stub_const("MetricUtil::SEGMENT_ANALYTICS", analytics)
      request = double(
        "request",
        user_agent: "Mozilla/5.0",
        fullpath: "/x",
        referer: nil,
        original_url: "https://app/x",
        remote_ip: "1.2.3.4"
      )
      allow(analytics).to receive(:identify).and_raise(StandardError.new("boom"))
      expect(LogUtil).to receive(:log_error).with(
        a_string_including("Failed to log to Segment"),
        hash_including(:exception, :event)
      )

      expect do
        MetricUtil.log_analytics_event("boom_event", user, {}, request)
      end.not_to raise_error
    end
  end

  describe "#post_to_airtable" do
    it "posts when both Airtable env vars are present" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("AIRTABLE_BASE_ID").and_return("base123")
      allow(ENV).to receive(:[]).with("AIRTABLE_ACCESS_TOKEN").and_return("token456")

      expect(MetricUtil).to receive(:https_post) do |uri, data, token|
        expect(uri.to_s).to include("base123")
        expect(uri.to_s).to include("api.airtable.com")
        expect(data).to eq("payload")
        expect(token).to eq("token456")
      end

      MetricUtil.post_to_airtable("My Table", "payload")
    end

    it "warns and does not post when the env vars are missing" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("AIRTABLE_BASE_ID").and_return(nil)
      allow(ENV).to receive(:[]).with("AIRTABLE_ACCESS_TOKEN").and_return(nil)

      expect(MetricUtil).not_to receive(:https_post)
      expect(Rails.logger).to receive(:warn).with(a_string_including("Cannot send to Airtable"))

      MetricUtil.post_to_airtable("My Table", "payload")
    end
  end

  describe "#https_post" do
    it "posts over the network on a background thread and joins successfully" do
      uri = URI.parse("https://api.example.com/path")
      ok_response = Net::HTTPSuccess.new("1.1", "200", "OK")
      allow(Rails.logger).to receive(:info)
      allow(Net::HTTP).to receive(:start).and_return(ok_response)

      thread = MetricUtil.send(:https_post, uri, '{"k":"v"}', "secret")
      thread.join

      expect(Net::HTTP).to have_received(:start).with(uri.hostname, uri.port, hash_including(use_ssl: true))
    end

    it "warns when the response is not successful" do
      uri = URI.parse("https://api.example.com/path")
      bad_response = Net::HTTPBadRequest.new("1.1", "400", "Bad Request")
      allow(Net::HTTP).to receive(:start).and_return(bad_response)
      allow(Rails.logger).to receive(:info)
      expect(Rails.logger).to receive(:warn).with(a_string_including("Unable to send data"))

      thread = MetricUtil.send(:https_post, uri, "{}", nil)
      thread.join
    end
  end
end
