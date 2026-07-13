# frozen_string_literal: true

require "rails_helper"

RSpec.describe AwsUtil do
  describe ".get_cloudwatch_url" do
    it "builds a region-scoped CloudWatch log-event-viewer URL from group + stream" do
      url = AwsUtil.get_cloudwatch_url("my-log-group", "my-log-stream")
      expect(url).to eq(
        "https://us-west-2.console.aws.amazon.com/cloudwatch/home?region=us-west-2" \
        "#logEventViewer:group=my-log-group;stream=my-log-stream"
      )
    end

    it "interpolates the configured AWS region on both sides" do
      url = AwsUtil.get_cloudwatch_url("g", "s")
      expect(url).to include("https://#{AwsUtil::AWS_REGION}.console.aws.amazon.com")
      expect(url).to include("region=#{AwsUtil::AWS_REGION}")
    end
  end

  describe ".get_sfn_execution_url" do
    it "builds a Step Functions execution-details URL from the ARN" do
      arn = "arn:aws:states:us-west-2:123456789012:execution:my-sfn:exec-1"
      url = AwsUtil.get_sfn_execution_url(arn)
      expect(url).to eq(
        "https://us-west-2.console.aws.amazon.com/states/home?region=us-west-2" \
        "#/executions/details/#{arn}"
      )
    end
  end
end
