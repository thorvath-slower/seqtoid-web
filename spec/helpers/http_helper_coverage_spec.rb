require "rails_helper"
require "webmock/rspec"

# Characterization specs for HttpHelper branches the existing http_helper_spec
# doesn't reach: the post_json failure path, get_json's silence_errors branch,
# and the entirely-untested .delete method (both success and failure). Spec-only.
RSpec.describe HttpHelper, type: :helper do
  describe ".post_json on a failed request" do
    before do
      stub_request(:post, "https://www.example.com")
        .to_return(status: 500, body: "boom")
    end

    it "raises HttpError carrying the status code" do
      expect do
        HttpHelper.post_json("https://www.example.com", { "a" => 1 })
      end.to raise_error(HttpHelper::HttpError) { |e| expect(e.status_code).to eq(500) }
    end
  end

  describe ".get_json with silence_errors" do
    before do
      stub_request(:get, "https://www.example.com")
        .to_return(status: 404)
    end

    it "still raises HttpError but does not log the warning when silence_errors is true" do
      expect(Rails.logger).not_to receive(:warn)

      expect do
        HttpHelper.get_json("https://www.example.com", {}, {}, true)
      end.to raise_error(HttpHelper::HttpError)
    end

    it "logs a warning when silence_errors is false (default)" do
      allow(Rails.logger).to receive(:warn)

      expect do
        HttpHelper.get_json("https://www.example.com", {}, {})
      end.to raise_error(HttpHelper::HttpError)

      expect(Rails.logger).to have_received(:warn).with(/GET request to .* failed/)
    end
  end

  describe ".delete" do
    it "returns nil on a successful DELETE request" do
      stub_request(:delete, "https://www.example.com/resource/1")
        .to_return(status: 200)

      result = HttpHelper.delete("https://www.example.com/resource/1",
                                 "Authorization" => "Bearer abc")

      expect(result).to be_nil
      expect(
        a_request(:delete, "https://www.example.com/resource/1")
          .with(headers: { "Authorization" => "Bearer abc" })
      ).to have_been_made
    end

    it "raises HttpError with the status code on a failed DELETE request" do
      stub_request(:delete, "https://www.example.com/resource/1")
        .to_return(status: 403, body: "forbidden")

      expect do
        HttpHelper.delete("https://www.example.com/resource/1", {})
      end.to raise_error(HttpHelper::HttpError) { |e| expect(e.status_code).to eq(403) }
    end
  end

  describe "HttpHelper::HttpError" do
    it "exposes the status_code passed to its constructor" do
      error = HttpHelper::HttpError.new("nope", 418)

      expect(error.status_code).to eq(418)
      expect(error.message).to eq("nope")
    end
  end
end
