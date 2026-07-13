require "rails_helper"

RSpec.describe SupportActionLogQuery, type: :service do
  # Build a fake Insights result row: an array of field objects (field/value).
  def result_row(timestamp, message)
    [
      instance_double("Aws::CloudWatchLogs::Types::ResultField", field: "@timestamp", value: timestamp),
      instance_double("Aws::CloudWatchLogs::Types::ResultField", field: "@message", value: message),
    ]
  end

  def action_log_line(payload)
    "[user_action] #{payload.to_json}"
  end

  let(:user_id) { 42 }
  let(:correlation_id) { "req-abc-123" }
  let(:window_start) { "2026-07-09T10:00:00Z" }
  let(:window_end) { "2026-07-09T10:30:00Z" }

  let(:client) { instance_double("Aws::CloudWatchLogs::Client") }

  def query(**overrides)
    described_class.new(
      user_id: user_id,
      correlation_id: correlation_id,
      window_start: window_start,
      window_end: window_end,
      log_group: "/seqtoid/support",
      poll_interval: 0,
      **overrides
    )
  end

  before do
    allow(AwsClient).to receive(:[]).with(:cloudwatchlogs).and_return(client)
  end

  describe "#recent_steps" do
    context "when no log group is configured" do
      it "returns nil without touching AWS (inert/gated)" do
        expect(AwsClient).not_to receive(:[])
        result = described_class.new(
          user_id: user_id,
          correlation_id: correlation_id,
          window_start: window_start,
          window_end: window_end,
          log_group: nil
        ).recent_steps
        expect(result).to be_nil
      end
    end

    context "when the query completes with action-log lines" do
      before do
        allow(client).to receive(:start_query)
          .and_return(instance_double("resp", query_id: "q-1"))

        rows = [
          result_row("2026-07-09 10:05:00.000",
                     action_log_line("czid.user_action.user_id" => 42, "action" => "project.create", "outcome" => "ok",
                                     "czid.user_action.request_id" => "req-abc-123", "czid.user_action.trace_id" => "trace-1")),
          result_row("2026-07-09 10:02:00.000",
                     action_log_line("czid.user_action.user_id" => 42, "action" => "bulk_download.create", "outcome" => "error",
                                     "error_class" => "RuntimeError")),
        ]
        allow(client).to receive(:get_query_results)
          .and_return(instance_double("results", status: "Complete", results: rows))
      end

      it "parses and returns steps ordered chronologically (oldest first)" do
        steps = query.recent_steps

        expect(steps.length).to eq(2)
        expect(steps.map { |s| s[:action] }).to eq(["bulk_download.create", "project.create"])
        expect(steps.first).to include(action: "bulk_download.create", outcome: "error", error_class: "RuntimeError")
        expect(steps.last).to include(action: "project.create", outcome: "ok", trace_id: "trace-1")
      end

      it "scopes the Insights query to the user id, correlation id, and marker" do
        expect(client).to receive(:start_query) do |args|
          expect(args[:log_group_name]).to eq("/seqtoid/support")
          expect(args[:query_string]).to include("[user_action]")
          expect(args[:query_string]).to include('"czid.user_action.user_id":42')
          expect(args[:query_string]).to include(correlation_id)
          # ISO8601 window coerced to epoch seconds.
          expect(args[:start_time]).to eq(Time.iso8601(window_start).to_i)
          expect(args[:end_time]).to eq(Time.iso8601(window_end).to_i)
          instance_double("resp", query_id: "q-1")
        end
        query.recent_steps
      end
    end

    context "when a result line is not a parseable action-log line" do
      before do
        allow(client).to receive(:start_query).and_return(instance_double("resp", query_id: "q-1"))
        rows = [
          result_row("2026-07-09 10:05:00.000", "some unrelated log line"),
          result_row("2026-07-09 10:06:00.000", "[user_action] {not valid json"),
          result_row("2026-07-09 10:07:00.000",
                     action_log_line("action" => "upload.create", "outcome" => "ok")),
        ]
        allow(client).to receive(:get_query_results)
          .and_return(instance_double("results", status: "Complete", results: rows))
      end

      it "skips unparseable rows and keeps the valid ones" do
        steps = query.recent_steps
        expect(steps.map { |s| s[:action] }).to eq(["upload.create"])
      end
    end

    context "when the query fails or times out" do
      it "returns nil on a Failed status" do
        allow(client).to receive(:start_query).and_return(instance_double("resp", query_id: "q-1"))
        allow(client).to receive(:get_query_results)
          .and_return(instance_double("results", status: "Failed", results: []))
        expect(query.recent_steps).to be_nil
      end

      it "returns nil when the query never completes within the poll budget" do
        allow(client).to receive(:start_query).and_return(instance_double("resp", query_id: "q-1"))
        allow(client).to receive(:get_query_results)
          .and_return(instance_double("results", status: "Running", results: []))
        expect(query(max_polls: 2).recent_steps).to be_nil
      end
    end

    context "when the AWS call raises" do
      it "swallows the error and returns nil (never breaks the caller)" do
        allow(client).to receive(:start_query).and_raise(StandardError, "boom")
        expect(Rails.logger).to receive(:error).with(/support_action_log_query/)
        expect(query.recent_steps).to be_nil
      end
    end
  end
end
