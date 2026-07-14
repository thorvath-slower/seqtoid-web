require "rails_helper"

# /revision reports the commit baked into the running image, so operators and CI can confirm
# which build an environment is actually serving. It must answer WITHOUT authentication (the
# check has to work before anyone logs in) and must not be swallowed by the '/:id' shortener.
RSpec.describe "GET /revision", type: :request do
  around do |example|
    original = ENV["GIT_VERSION"]
    example.run
    if original.nil?
      ENV.delete("GIT_VERSION")
    else
      ENV["GIT_VERSION"] = original
    end
  end

  it "returns the baked-in commit as plain text, unauthenticated" do
    ENV["GIT_VERSION"] = "abc12345"

    get "/revision"

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/plain")
    expect(response.body).to eq("abc12345")
  end

  it "reports 'unknown' rather than failing when the image carries no commit" do
    ENV.delete("GIT_VERSION")

    get "/revision"

    expect(response).to have_http_status(:ok)
    expect(response.body).to eq("unknown")
  end

  it "is not captured by the shortener catch-all" do
    ENV["GIT_VERSION"] = "deadbeef"

    get "/revision"

    # The shortener would 302/404 on an unknown slug; a 200 body of the commit proves the
    # route resolved ahead of it.
    expect(response).to have_http_status(:ok)
    expect(response.body).to eq("deadbeef")
  end
end
