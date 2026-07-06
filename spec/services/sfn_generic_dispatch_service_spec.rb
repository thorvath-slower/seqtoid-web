require 'rails_helper'
require 'json'

require "support/common_stub_constants"

RSpec.describe SfnGenericDispatchService, type: :service do
  let(:fake_account_id) { "123456789012" }
  let(:fake_sfn_arn) { "fake:sfn:arn" }
  let(:fake_wdl_version) { "1.2.3" }
  let(:cg_workflow) { WorkflowRun::WORKFLOW[:consensus_genome] }

  let(:inputs_json) { { "some_input" => "value" } }
  let(:output_prefix) { "s3://fake-bucket/output/prefix" }

  let(:fake_states_client) do
    Aws::States::Client.new(
      stub_responses: {
        start_execution: {
          execution_arn: CommonStubConstants::FAKE_SFN_EXECUTION_ARN,
          start_date: Time.zone.now,
        },
      }
    )
  end
  let(:fake_sts_client) do
    Aws::STS::Client.new(
      stub_responses: {
        get_caller_identity: { account: fake_account_id },
      }
    )
  end

  let(:project) { create(:project) }
  let(:sample) { create(:sample, project: project) }
  let(:workflow_run) { create(:workflow_run, sample: sample, workflow: cg_workflow) }

  before do
    Aws.config[:stub_responses] = true
    @mock_aws_clients = { states: fake_states_client, sts: fake_sts_client }
    allow(AwsClient).to receive(:[]) { |client| @mock_aws_clients[client] }
  end

  describe "#initialize (config validation branches)" do
    context "when the SFN ARN is missing" do
      it "raises SfnArnMissingError" do
        expect do
          SfnGenericDispatchService.new(
            workflow_run,
            inputs_json: inputs_json,
            output_prefix: output_prefix
          )
        end.to raise_error(SfnGenericDispatchService::SfnArnMissingError, /SFN_SINGLE_WDL_ARN/)
      end
    end

    context "when the SFN ARN is present but the WDL version is missing" do
      before do
        create(:app_config, key: AppConfig::SFN_SINGLE_WDL_ARN, value: fake_sfn_arn)
      end

      # CHARACTERIZATION (pins current, buggy behavior — see app bug below).
      #
      # The intended behavior is to raise SfnVersionMissingError naming the
      # workflow. In practice, the missing-version branch is never reached:
      # app/services/sfn_generic_dispatch_service.rb:33 calls
      #   AppConfigHelper.get_workflow_version(workflow_name)
      # using a bare `workflow_name` (no `@`). No such local variable or method
      # exists (the ivar is `@workflow_name`), so a NameError is raised before
      # the version check. This spec pins that current behavior so the wave is
      # green; the app bug is reported separately (do not fix app code here).
      it "raises NameError from the bare `workflow_name` reference (app bug)" do
        expect do
          SfnGenericDispatchService.new(
            workflow_run,
            inputs_json: inputs_json,
            output_prefix: output_prefix
          )
        end.to raise_error(NameError, /workflow_name/)
      end
    end

    context "when a version is passed explicitly" do
      before do
        create(:app_config, key: AppConfig::SFN_SINGLE_WDL_ARN, value: fake_sfn_arn)
      end

      it "uses the passed version and does not raise even when App Config has none" do
        expect do
          SfnGenericDispatchService.new(
            workflow_run,
            inputs_json: inputs_json,
            output_prefix: output_prefix,
            version: fake_wdl_version
          )
        end.not_to raise_error
      end
    end
  end

  describe "#call" do
    subject do
      SfnGenericDispatchService.call(
        workflow_run,
        inputs_json: inputs_json,
        output_prefix: output_prefix,
        version: fake_wdl_version
      )
    end

    before do
      create(:app_config, key: AppConfig::SFN_SINGLE_WDL_ARN, value: fake_sfn_arn)
    end

    it "returns the built input json and the execution arn" do
      result = subject
      expect(result[:sfn_execution_arn]).to eq(CommonStubConstants::FAKE_SFN_EXECUTION_ARN)
      expect(result[:sfn_input_json]).to be_a(Hash)
    end

    it "builds the RUN_WDL_URI with the workflow name, version and default wdl_file_name" do
      expect(subject).to include_json(
        sfn_input_json: {
          RUN_WDL_URI: "s3://#{S3_WORKFLOWS_BUCKET}/#{cg_workflow}-v#{fake_wdl_version}/#{cg_workflow}.wdl.zip",
          OutputPrefix: output_prefix,
        }
      )
    end

    it "merges the docker_image_id into the Run inputs alongside the caller inputs" do
      expect(subject).to include_json(
        sfn_input_json: {
          Input: {
            Run: {
              docker_image_id: "#{fake_account_id}.dkr.ecr.#{AwsUtil::AWS_REGION}.amazonaws.com/#{cg_workflow}:v#{fake_wdl_version}",
              some_input: "value",
            },
          },
        }
      )
    end

    context "when a custom wdl_file_name is supplied" do
      subject do
        SfnGenericDispatchService.call(
          workflow_run,
          inputs_json: inputs_json,
          output_prefix: output_prefix,
          wdl_file_name: WorkflowRun::DEFAULT_WDL_FILE_NAME,
          version: fake_wdl_version
        )
      end

      it "uses the supplied wdl_file_name in the RUN_WDL_URI" do
        expect(subject).to include_json(
          sfn_input_json: {
            RUN_WDL_URI: "s3://#{S3_WORKFLOWS_BUCKET}/#{cg_workflow}-v#{fake_wdl_version}/#{WorkflowRun::DEFAULT_WDL_FILE_NAME}.wdl.zip",
          }
        )
      end
    end

    context "when start_execution returns a blank execution arn" do
      before do
        @mock_aws_clients[:states] = Aws::States::Client.new(
          stub_responses: {
            start_execution: {
              execution_arn: "",
              start_date: Time.zone.now,
            },
          }
        )
      end

      it "marks the workflow_run failed and re-raises" do
        expect { subject }.to raise_error(StandardError)
        expect(workflow_run.reload.status).to eq(WorkflowRun::STATUS[:failed])
      end
    end

    context "when start_execution itself errors" do
      before do
        @mock_aws_clients[:states].stub_responses(:start_execution, Aws::States::Errors::InvalidArn.new(nil, nil))
      end

      # CHARACTERIZATION (pins current, buggy behavior — see app bug below).
      #
      # The intended behavior is to log and re-raise the original SFN error
      # (Aws::States::Errors::InvalidArn). In practice the rescue block in
      # app/services/sfn_generic_dispatch_service.rb:65 interpolates a bare
      # `workflow_name` (no `@`) into the log message. No such local variable
      # or method exists, so building the log message itself raises a
      # NameError, which replaces (masks) the original InvalidArn. This spec
      # pins that current behavior; the app bug is reported separately.
      it "raises NameError while logging in the rescue block (app bug masks the original error)" do
        expect { subject }.to raise_error(NameError, /workflow_name/)
      end
    end
  end
end
