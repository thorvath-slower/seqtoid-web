// CZID-462 (#586) coverage: app/assets/src/components/utils/metadata.ts
import {
  formatSendValue,
  processMetadata,
  processMetadataTypes,
  returnHipaaCompliantMetadata,
} from "../app/assets/src/components/utils/metadata";

describe("utils/metadata.ts", () => {
  describe("processMetadata", () => {
    it("returns an empty object for missing metadata", () => {
      expect(processMetadata({ metadata: null, flatten: false })).toEqual({});
    });
    it("keys metadata by key, picking the base_type validated value", () => {
      const raw = [
        {
          key: "collection_location",
          base_type: "string",
          string_validated_value: "SF",
        },
        { key: "sample_date", base_type: "date", raw_value: "2024-01-01" },
      ] as any;
      expect(processMetadata({ metadata: raw, flatten: false })).toEqual({
        collection_location: "SF",
        sample_date: "2024-01-01",
      });
    });
    it("flattens location objects to their name when flatten is true", () => {
      const raw = [
        {
          key: "collection_location",
          base_type: "location",
          location_validated_value: { name: "San Francisco" },
        },
      ] as any;
      expect(processMetadata({ metadata: raw, flatten: true })).toEqual({
        collection_location: "San Francisco",
      });
    });
  });

  describe("processMetadataTypes", () => {
    it("returns an empty object when types are missing", () => {
      expect(processMetadataTypes(null)).toEqual({});
    });
    it("keys metadata types by key", () => {
      const types = [{ key: "host_age" }, { key: "sex" }] as any;
      expect(processMetadataTypes(types)).toEqual({
        host_age: { key: "host_age" },
        sex: { key: "sex" },
      });
    });
  });

  describe("returnHipaaCompliantMetadata", () => {
    it("caps host_age at the max input with a >= prefix", () => {
      expect(returnHipaaCompliantMetadata("host_age", "95")).toBe("≥ 90");
    });
    it("leaves host_age below the max unchanged", () => {
      expect(returnHipaaCompliantMetadata("host_age", "40")).toBe("40");
    });
    it("leaves non-host_age fields unchanged", () => {
      expect(returnHipaaCompliantMetadata("sex", "Female")).toBe("Female");
    });
  });

  describe("formatSendValue", () => {
    it("wraps object values in the location input key", () => {
      const value = { name: "SF" } as any;
      expect(formatSendValue(value)).toEqual({
        query_SampleMetadata_metadata_items_location_validated_value_oneOf_1_Input:
          value,
      });
    });
    it("stringifies scalar values under the String key", () => {
      expect(formatSendValue(42)).toEqual({ String: "42" });
      expect(formatSendValue("text")).toEqual({ String: "text" });
    });
  });
});
