# frozen_string_literal: true

require "rails_helper"

# Instrument.snippet wraps ActiveSupport::Notifications for timing a code block.
# We subscribe to the ".snippet" event to assert the payload is populated
# correctly on both the happy path and the exception path.
RSpec.describe Instrument do
  def capture_event(event_name)
    captured = nil
    subscriber = ActiveSupport::Notifications.subscribe(event_name) do |*args|
      captured = ActiveSupport::Notifications::Event.new(*args)
    end
    yield
    captured
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  describe ".snippet" do
    it "raises ArgumentError when name is not a String" do
      expect { Instrument.snippet(name: :not_a_string) { nil } }
        .to raise_error(ArgumentError, /not a String/)
    end

    it "yields the payload to the block and returns nothing surprising" do
      yielded = nil
      Instrument.snippet(name: "work", payload: { foo: 1 }) { |p| yielded = p }
      expect(yielded).to include(foo: 1)
    end

    it "instruments a '<name>.snippet' event and records the snippet name in the payload" do
      event = capture_event("job.snippet") do
        Instrument.snippet(name: "job") { 1 + 1 }
      end
      expect(event).not_to be_nil
      expect(event.name).to eq("job.snippet")
      expect(event.payload[:snippet]).to eq("job")
    end

    it "records cloudwatch_namespace and extra_dimensions when provided" do
      event = capture_event("m.snippet") do
        Instrument.snippet(name: "m", cloudwatch_namespace: "NS",
                                     extra_dimensions: [{ name: "d", value: "v" }]) { nil }
      end
      expect(event.payload[:cloudwatch_namespace]).to eq("NS")
      expect(event.payload[:extra_dimensions]).to eq([{ name: "d", value: "v" }])
    end

    it "omits cloudwatch_namespace/extra_dimensions from the payload when empty" do
      event = capture_event("m2.snippet") do
        Instrument.snippet(name: "m2") { nil }
      end
      expect(event.payload).not_to have_key(:cloudwatch_namespace)
      expect(event.payload).not_to have_key(:extra_dimensions)
    end

    it "re-raises the block's exception and captures exception details in the payload" do
      captured = nil
      subscriber = ActiveSupport::Notifications.subscribe("err.snippet") do |*args|
        captured = ActiveSupport::Notifications::Event.new(*args)
      end
      begin
        Instrument.snippet(name: "err") { raise ArgumentError, "bad" }
      rescue ArgumentError
        # expected
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end
      expect(captured.payload[:exception]).to eq(["ArgumentError", "bad"])
      expect(captured.payload[:exception_object]).to be_a(ArgumentError)
    end
  end
end
