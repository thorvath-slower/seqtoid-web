require "rails_helper"

RSpec.describe ProjectsHelper, type: :helper do
  describe ".sanitize_project_name" do
    it "keeps letters, numbers, underscores, dashes, and spaces" do
      expect(ProjectsHelper.sanitize_project_name("My_Project-1 2")).to eq("My_Project-1 2")
    end

    it "replaces disallowed characters with dashes" do
      expect(ProjectsHelper.sanitize_project_name("bad/name?!")).to eq("bad-name--")
    end

    it "returns an empty string unchanged" do
      expect(ProjectsHelper.sanitize_project_name("")).to eq("")
    end
  end

  describe ".sanitize_project_description" do
    it "strips HTML tags from the description" do
      expect(ProjectsHelper.sanitize_project_description("<b>hello</b> world"))
        .to eq("hello world")
    end

    it "leaves plain text unchanged" do
      expect(ProjectsHelper.sanitize_project_description("just text")).to eq("just text")
    end
  end
end
