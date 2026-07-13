require 'rails_helper'

# Regression coverage for the public legal/footer pages served by SupportController.
# These are click-through targets from the footer + user menu ("Terms of Use",
# "Privacy Notice", "Recent Changes") and must render for signed-out visitors.
RSpec.describe SupportController, type: :controller do
  render_views

  describe "GET #terms" do
    it "renders the Terms of Use page (200) for a signed-out visitor" do
      get :terms
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("TermsOfUse")
    end
  end

  describe "GET #privacy" do
    it "renders the Privacy Notice page (200) for a signed-out visitor" do
      get :privacy
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("PrivacyNotice")
    end
  end

  describe "GET #terms_changes" do
    it "renders the Terms Changes page (200) for a signed-out visitor" do
      get :terms_changes
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("TermsChanges")
    end
  end
end
