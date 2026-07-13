require "rails_helper"

RSpec.describe ApplicationRecord, type: :model do
  describe ".safe_order_dir" do
    it "passes valid directions through" do
      expect(ApplicationRecord.safe_order_dir("asc")).to eq("asc")
      expect(ApplicationRecord.safe_order_dir("desc")).to eq("desc")
    end

    it "normalizes case to lowercase" do
      expect(ApplicationRecord.safe_order_dir("ASC")).to eq("asc")
      expect(ApplicationRecord.safe_order_dir("Desc")).to eq("desc")
    end

    it "falls back to asc for invalid, empty, or nil input" do
      expect(ApplicationRecord.safe_order_dir("")).to eq("asc")
      expect(ApplicationRecord.safe_order_dir(nil)).to eq("asc")
      expect(ApplicationRecord.safe_order_dir("foo")).to eq("asc")
    end

    it "falls back to asc for SQL-injection attempts (defense-in-depth for ORDER BY interpolation)" do
      expect(ApplicationRecord.safe_order_dir("asc; DROP TABLE samples; --")).to eq("asc")
      expect(ApplicationRecord.safe_order_dir("asc) UNION SELECT password FROM users --")).to eq("asc")
    end
  end

  describe ".mysql_nulls" do
    it "returns no NULLS clause (MySQL orders NULLs natively)" do
      expect(ApplicationRecord.mysql_nulls("asc")).to eq("")
      expect(ApplicationRecord.mysql_nulls("desc")).to eq("")
    end
  end
end
