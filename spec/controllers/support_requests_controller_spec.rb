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
          diagnostics: {
            release: "abc1234",
            environment: "test",
            url: "/samples/123",
            userAgent: "Mozilla/5.0",
          },
        }
      end

      it "returns 201 created and records the support request" do
        expect(LogUtil).to receive(:log_message).with(
          "Support request from user #{@user.id}",
          hash_including(event: "support_request", user_id: @user.id, user_email: @user.email)
        )

        post :create, params: valid_params

        expect(response).to have_http_status(:created)
        json_response = JSON.parse(response.body)
        expect(json_response["status"]).to eq("ok")
      end

      it "succeeds when only a description is provided (diagnostics optional)" do
        post :create, params: { description: "Something is broken." }
        expect(response).to have_http_status(:created)
      end

      it "succeeds with an empty description (diagnostics-only report)" do
        post :create, params: { diagnostics: { url: "/home" } }
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
