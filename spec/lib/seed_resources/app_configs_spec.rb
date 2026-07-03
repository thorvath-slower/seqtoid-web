require "rails_helper"

# Regression coverage for #385: the SFN state-machine ARNs seeded here used to
# hardcode the "dev" deployment stage, so seeding in the staging account produced
# `idseq-swipe-dev-...` in the staging account -> Aws::States::StateMachineDoesNotExist.
# The stage is now derived from ENV["ENVIRONMENT"] (defaulting to "dev"), so each
# account/env seeds its own state machine name.
RSpec.describe SeedResource::AppConfigs do
  describe "#sfn_configs" do
    let(:account_id) { "030998640247" }

    subject(:sfn_configs) { described_class.new.send(:sfn_configs) }

    around do |example|
      original_account = ENV["AWS_ACCOUNT_ID"]
      original_environment = ENV["ENVIRONMENT"]
      ENV["AWS_ACCOUNT_ID"] = account_id
      example.run
      ENV["AWS_ACCOUNT_ID"] = original_account
      ENV["ENVIRONMENT"] = original_environment
    end

    context "when ENVIRONMENT is set (e.g. staging)" do
      before { ENV["ENVIRONMENT"] = "staging" }

      it "seeds ARNs that point at the environment's own state machine" do
        sfn_configs

        expect(AppConfigHelper.get_app_config(AppConfig::SFN_SINGLE_WDL_ARN))
          .to eq("arn:aws:states:us-west-2:#{account_id}:stateMachine:idseq-swipe-staging-default-wdl")
        expect(AppConfigHelper.get_app_config(AppConfig::SFN_ARN))
          .to eq("arn:aws:states:us-west-2:#{account_id}:stateMachine:idseq-swipe-staging-short-read-mngs-wdl")
        expect(AppConfigHelper.get_app_config(AppConfig::SFN_MNGS_ARN))
          .to eq("arn:aws:states:us-west-2:#{account_id}:stateMachine:idseq-swipe-staging-short-read-mngs-wdl")
        expect(AppConfigHelper.get_app_config(AppConfig::SFN_CG_ARN))
          .to eq("arn:aws:states:us-west-2:#{account_id}:stateMachine:idseq-swipe-staging-default-wdl")
      end

      it "does not seed a dev-named state machine in a non-dev account" do
        sfn_configs

        [AppConfig::SFN_SINGLE_WDL_ARN, AppConfig::SFN_ARN, AppConfig::SFN_MNGS_ARN, AppConfig::SFN_CG_ARN].each do |key|
          expect(AppConfigHelper.get_app_config(key)).not_to include("idseq-swipe-dev-")
        end
      end
    end

    context "when ENVIRONMENT is unset (local/dev parity)" do
      before { ENV["ENVIRONMENT"] = nil }

      it "defaults the stage to dev so existing dev behaviour is unchanged" do
        sfn_configs

        expect(AppConfigHelper.get_app_config(AppConfig::SFN_SINGLE_WDL_ARN))
          .to eq("arn:aws:states:us-west-2:#{account_id}:stateMachine:idseq-swipe-dev-default-wdl")
      end
    end

    context "when ENVIRONMENT is blank" do
      before { ENV["ENVIRONMENT"] = "" }

      it "treats a blank value the same as unset and defaults to dev" do
        sfn_configs

        expect(AppConfigHelper.get_app_config(AppConfig::SFN_ARN))
          .to eq("arn:aws:states:us-west-2:#{account_id}:stateMachine:idseq-swipe-dev-short-read-mngs-wdl")
      end
    end
  end
end
