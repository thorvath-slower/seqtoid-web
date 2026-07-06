require "rails_helper"

# Coverage for DateHelper. The parse_date methods are instance methods mixed
# into views/controllers, so exercise them through the `helper` proxy.
RSpec.describe DateHelper, type: :helper do
  describe "#parse_date_helper" do
    it "returns nil when the string does not match the format regex" do
      expect(helper.parse_date_helper("not-a-date", DateHelper::DATE_STANDARD)).to be_nil
    end

    it "parses a YYYY-MM-DD string with the standard format" do
      expect(helper.parse_date_helper("2020-03-15", DateHelper::DATE_STANDARD))
        .to eq(Date.new(2020, 3, 15))
    end

    it "returns nil when the regex matches but strptime raises (impossible date)" do
      # 2020-13-40 matches the loose \d{4}-\d{1,2}-\d{1,2} regex but is not a real
      # date, so Date.strptime raises ArgumentError and the rescue returns nil.
      expect(helper.parse_date_helper("2020-13-40", DateHelper::DATE_STANDARD)).to be_nil
    end
  end

  describe "#parse_date" do
    context "when day components are allowed (default)" do
      it "parses the standard YYYY-MM-DD format" do
        expect(helper.parse_date("2021-06-02")).to eq(Date.new(2021, 6, 2))
      end

      it "parses the standard YYYY-MM month-only format" do
        expect(helper.parse_date("2021-06")).to eq(Date.new(2021, 6, 1))
      end

      it "parses the alternate MM/DD/YY format" do
        expect(helper.parse_date("06/02/21")).to eq(Date.new(2021, 6, 2))
      end

      it "parses the alternate MM/YYYY month-only format" do
        expect(helper.parse_date("06/2021")).to eq(Date.new(2021, 6, 1))
      end

      it "raises ArgumentError when nothing matches" do
        expect { helper.parse_date("garbage") }.to raise_error(ArgumentError, "Date could not be parsed")
      end
    end

    context "when day components are disallowed (allow_day = false)" do
      it "parses a month-only standard date" do
        expect(helper.parse_date("2021-06", false)).to eq(Date.new(2021, 6, 1))
      end

      it "parses a month-only alternate date" do
        expect(helper.parse_date("06/2021", false)).to eq(Date.new(2021, 6, 1))
      end

      it "rejects a full day-precision date (not in the allowed month-only formats)" do
        expect { helper.parse_date("2021-06-02", false) }
          .to raise_error(ArgumentError, "Date could not be parsed")
      end
    end
  end
end
