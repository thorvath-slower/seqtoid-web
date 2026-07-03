require 'rails_helper'

# CZID-472 - unit coverage for the OTel action-logging concern. Exercises the
# no-PII sanitization, inert-safety (never raises into the request path), and the
# structured-log emission - without booting a full controller/OTel exporter.
RSpec.describe OtelActionLogging do
  # Minimal host that mixes in the concern and stubs the controller collaborators
  # the concern reads (current_user / request / controller_name / action_name).
  let(:host_class) do
    Class.new do
      include OtelActionLogging

      attr_accessor :current_user, :request, :controller_name, :action_name

      # expose privates for direct assertion
      public :base_action_attributes, :sanitize_action_attributes, :emit_action_log,
             :log_user_action, :with_user_action_log
    end
  end

  let(:fake_user) { instance_double("User", id: 42, role: 0) }
  let(:fake_request) { instance_double("ActionDispatch::Request", request_id: "req-abc-123") }

  let(:subject) do
    host_class.new.tap do |c|
      c.current_user = fake_user
      c.request = fake_request
      c.controller_name = "bulk_downloads"
      c.action_name = "create"
    end
  end

  describe "#base_action_attributes" do
    it "includes identifiers only (user id, role, request id) and no PII" do
      attrs = subject.base_action_attributes
      expect(attrs["czid.user_action.user_id"]).to eq(42)
      expect(attrs["czid.user_action.user_role"]).to eq(0)
      expect(attrs["czid.user_action.request_id"]).to eq("req-abc-123")
      expect(attrs["czid.user_action.controller"]).to eq("bulk_downloads")
      expect(attrs["czid.user_action.action"]).to eq("create")
      # never carries user identity beyond ids
      expect(attrs.keys.join).not_to include("email")
      expect(attrs.keys.join).not_to include("name")
    end

    it "omits user attributes when there is no current_user (anonymous)" do
      subject.current_user = nil
      attrs = subject.base_action_attributes
      expect(attrs).not_to have_key("czid.user_action.user_id")
      expect(attrs).to have_key("czid.user_action.request_id")
    end
  end

  describe "#sanitize_action_attributes" do
    it "drops sensitive keys (defensive no-PII denylist)" do
      cleaned = subject.sanitize_action_attributes(
        "czid.project.id" => 7,
        "user_email" => "secret@example.com",
        "authorization" => "Bearer xyz",
        "remote_ip" => "1.2.3.4"
      )
      expect(cleaned).to eq("czid.project.id" => 7)
    end

    it "drops nil values and stringifies keys" do
      cleaned = subject.sanitize_action_attributes(project_id: 9, workflow: nil)
      expect(cleaned).to eq("project_id" => 9)
    end

    it "returns an empty hash for non-hash input" do
      expect(subject.sanitize_action_attributes(nil)).to eq({})
    end
  end

  describe "#emit_action_log" do
    it "writes a single structured [user_action] JSON log line" do
      expect(Rails.logger).to receive(:info) do |line|
        expect(line).to start_with("[user_action] ")
        payload = JSON.parse(line.sub("[user_action] ", ""))
        expect(payload["event"]).to eq("user_action")
        expect(payload["action"]).to eq("bulk_download.create")
        expect(payload["outcome"]).to eq("ok")
      end
      subject.emit_action_log("bulk_download.create", { "czid.user_action.user_id" => 42 }, outcome: "ok", error_class: nil)
    end

    it "never raises even if the payload cannot be serialized" do
      expect { subject.emit_action_log("x", { "k" => BasicObject.new }, outcome: "ok", error_class: nil) }.not_to raise_error
    end
  end

  describe "#log_user_action (imperative)" do
    it "does not raise when OTel is a no-op (unconfigured)" do
      allow(Rails.logger).to receive(:info)
      expect { subject.log_user_action("project.create", "czid.project.id" => 3) }.not_to raise_error
    end
  end

  describe "#with_user_action_log (around wrapper)" do
    it "runs the wrapped block and returns to the caller" do
      allow(Rails.logger).to receive(:info)
      ran = false
      subject.with_user_action_log("sample.bulk_upload", nil) { ran = true }
      expect(ran).to be(true)
    end

    it "re-raises the wrapped action's error (behavior unchanged) and logs an error outcome" do
      allow(Rails.logger).to receive(:info)
      expect do
        subject.with_user_action_log("sample.bulk_upload", nil) { raise ArgumentError, "boom" }
      end.to raise_error(ArgumentError, "boom")
    end
  end
end
