# frozen_string_literal: true

require "rails_helper"

RSpec.describe HashUtil do
  describe ".flat_hash" do
    it "flattens a nested hash to path-array keys (the documented example)" do
      input = { a: { b: { c: 1, d: 2 }, e: 3 }, f: 4 }
      expect(HashUtil.flat_hash(input)).to eq(
        [:a, :b, :c] => 1,
        [:a, :b, :d] => 2,
        [:a, :e] => 3,
        [:f] => 4
      )
    end

    it "returns a single empty-path entry for a non-hash value" do
      expect(HashUtil.flat_hash(5)).to eq([] => 5)
    end

    it "handles an already-flat hash" do
      expect(HashUtil.flat_hash(a: 1, b: 2)).to eq([:a] => 1, [:b] => 2)
    end

    it "treats an empty hash as producing no leaf entries" do
      expect(HashUtil.flat_hash({})).to eq({})
    end

    it "preserves array and nil leaf values without descending into them" do
      expect(HashUtil.flat_hash(a: { b: [1, 2] }, c: nil)).to eq(
        [:a, :b] => [1, 2],
        [:c] => nil
      )
    end
  end

  describe ".to_struct" do
    it "converts a hash into an OpenStruct with dotted access" do
      struct = HashUtil.to_struct("name" => "seqtoid", "count" => 3)
      expect(struct.name).to eq("seqtoid")
      expect(struct.count).to eq(3)
    end

    it "converts nested hashes into nested OpenStructs" do
      struct = HashUtil.to_struct("outer" => { "inner" => "value" })
      expect(struct.outer.inner).to eq("value")
    end

    it "converts hashes inside arrays into OpenStructs" do
      struct = HashUtil.to_struct("items" => [{ "id" => 1 }, { "id" => 2 }])
      expect(struct.items.map(&:id)).to eq([1, 2])
    end
  end
end
