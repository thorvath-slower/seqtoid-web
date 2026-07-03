require 'rails_helper'

RSpec.describe SupportRequestsController, type: :controller do
  context "when the user is signed in" do
    before do
      @user = create(:user)
      sign_in @user
    end

    describe "POST #create" do
      let(:valid_params) do
        {
          description: "The report page will not load for my sample.",
          quick_report: {
            errorName: "TypeError: cannot read property 'foo' of undefined",
            task: "Bulk download",
            project: "Project 7",
            accountName: "Test User",
          },
          diagnostics: {
            release: "abc1234",
            environment: "test",
            route: "/bulk_downloads",
            url: "/bulk_downloads",
            userAgent: "Mozilla/5.0",
          },
        }
      end

      it "returns 201 created and records the rich, support-side payload" do
        expect(LogUtil).to receive(:log_message).with(
          a_string_matching(/Support request from user #{@user.id}/),
          hash_including(
            event: "support_request",
            user_id: @user.id,
            user_email: @user.email,
            # user-facing quick report fields
            error: "TypeError: cannot read property 'foo' of undefined",
            task: "Bulk download",
            project: "Project 7",
            account_name: "Test User",
          )
        )

        post :create, params: valid_params

        expect(response).to have_http_status(:created)
        json_response = JSON.parse(response.body)
        expect(json_response["status"]).to eq("ok")
        expect(json_response["correlation_id"]).to be_present
      end

      it "attaches a correlation id, summary, matched runbook, and log deep-links" do
        captured = nil
        allow(LogUtil).to receive(:log_message) do |_msg, **payload|
          captured = payload
        end

        post :create, params: valid_params

        expect(captured[:correlation_id]).to be_present
        expect(captured[:summary]).to include("Bulk download")
        # A bulk-download error should match the bulk_download runbook.
        expect(captured[:runbook][:id]).to eq("bulk_download_failure")
        expect(captured[:runbook][:runbook]).to be_present
        # Log deep-links are constructed and filtered to this session/user.
        expect(captured[:log_links][:cloudwatch_logs_insights]).to include("cloudwatch")
        expect(captured[:log_links][:otel_dashboard]).to include(captured[:correlation_id])
        # The OTel step-by-step is scaffolded pending #472 (not faked).
        expect(captured[:action_log_steps]).to be_nil
        expect(captured[:log_links][:otel_action_log]).to be_nil
      end

      it "falls back to a generic runbook when nothing matches" do
        captured = nil
        allow(LogUtil).to receive(:log_message) do |_msg, **payload|
          captured = payload
        end

        post :create, params: {
          quick_report: { errorName: "Something odd", task: "Home" },
          diagnostics: { route: "/home" },
        }

        expect(captured[:runbook][:id]).to eq("generic_triage")
      end

      it "succeeds when only a description is provided (quick report / diagnostics optional)" do
        post :create, params: { description: "Something is broken." }
        expect(response).to have_http_status(:created)
      end

      it "succeeds with an empty description (report without free-text)" do
        post :create, params: { quick_report: { task: "Home" } }
        expect(response).to have_http_status(:created)
      end
    end
  end

  context "when the user is not signed in" do
    describe "POST #create" do
      it "does not record the request and redirects to login" do
        expect(LogUtil).not_to receive(:log_message)
        post :create, params: { description: "hello" }
        expect(response).to have_http_status(:redirect)
      end
    end
  end
end
