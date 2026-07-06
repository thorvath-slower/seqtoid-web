# frozen_string_literal: true

require "rails_helper"

# Syscall shells out via Open3. These specs use real, portable commands (echo, cat,
# grep, false, a bad binary) so we exercise the actual success/failure/error paths
# rather than mocking Open3 away.
RSpec.describe Syscall do
  describe ".run" do
    it "returns stdout on success" do
      expect(Syscall.run("echo", "hello")).to eq("hello\n")
    end

    it "returns nil and logs when the command exits non-zero" do
      expect(Rails.logger).to receive(:error).with(/Syscall.run failed/)
      expect(Syscall.run("false")).to be_nil
    end

    it "returns nil and logs when the command cannot be executed" do
      expect(Rails.logger).to receive(:error).at_least(:once)
      expect(Syscall.run("this_binary_does_not_exist_zzz")).to be_nil
    end

    it "passes each argument separately (no shell interpolation)" do
      # If args were joined into a shell string, the '$' would expand; here it's literal.
      expect(Syscall.run("echo", "$HOME")).to eq("$HOME\n")
    end
  end

  describe ".run_in_dir" do
    it "runs the command in the given directory" do
      out = Syscall.run_in_dir("/", "pwd")
      expect(out.strip).to eq("/")
    end

    it "returns nil and logs on failure" do
      expect(Rails.logger).to receive(:error).with(/Syscall.run_in_dir failed/)
      expect(Syscall.run_in_dir("/", "false")).to be_nil
    end
  end

  describe ".pipe_with_output" do
    it "streams output through a pipeline of commands" do
      out = Syscall.pipe_with_output(["echo", "hi\nbye"], ["grep", "hi"])
      expect(out).to eq("hi\n")
    end

    it "returns nil and logs when the pipeline raises" do
      expect(Rails.logger).to receive(:error).at_least(:once)
      expect(Syscall.pipe_with_output(["no_such_cmd_zzz"])).to be_nil
    end
  end

  describe ".pipe" do
    it "returns [true, stderr] when every command in the pipeline succeeds" do
      success, stderr = Syscall.pipe(["echo", "hello"], ["cat"])
      expect(success).to be(true)
      expect(stderr).to eq("")
    end

    it "returns false when a command in the pipeline fails" do
      success, = Syscall.pipe(["echo", "hi"], ["grep", "nomatch"])
      expect(success).to be(false)
    end
  end
end
