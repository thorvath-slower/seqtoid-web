// #586 (epic #462) coverage: metadata.ts normalizes server metadata responses
// (date vs validated-value branch, optional flatten), keys metadata types, applies
// HIPAA age-capping, and shapes send values. Branch-rich and pure.
import {
  formatSendValue,
  processMetadata,
  processMetadataTypes,
  returnHipaaCompliantMetadata,
} from "../app/assets/src/components/utils/metadata";

describe("processMetadata", () => {
  it("returns an empty object when metadata is null", () => {
    expect(processMetadata({ metadata: null, flatten: false })).toEqual({});
  });

  it("uses raw_value for date fields and *_validated_value otherwise", () => {
    const metadata = [
      { key: "collection_date", base_type: "date", raw_value: "2024-01-01" },
      { key: "host_age", base_type: "number", number_validated_value: 42 },
    ] as any;
    expect(processMetadata({ metadata, flatten: false })).toEqual({
      collection_date: "2024-01-01",
      host_age: 42,
    });
  });

  it("flattens object values to their .name when flatten is true", () => {
    const metadata = [
      {
        key: "collection_location",
        base_type: "location",
        location_validated_value: { name: "San Francisco", id: 1 },
      },
    ] as any;
    expect(processMetadata({ metadata, flatten: true })).toEqual({
      collection_location: "San Francisco",
    });
  });
});

describe("processMetadataTypes", () => {
  it("returns an empty object for nullish input", () => {
    expect(processMetadataTypes(null)).toEqual({});
    expect(processMetadataTypes(undefined)).toEqual({});
  });

  it("keys the metadata types by their key field", () => {
    const types = [
      { key: "host_age", name: "Host Age" },
      { key: "sex", name: "Sex" },
    ] as any;
    expect(processMetadataTypes(types)).toEqual({
      host_age: { key: "host_age", name: "Host Age" },
      sex: { key: "sex", name: "Sex" },
    });
  });
});

describe("returnHipaaCompliantMetadata", () => {
  it("caps host_age at or above the max input", () => {
    const capped = returnHipaaCompliantMetadata("host_age", "95");
    expect(capped).not.toBe("95");
    expect(capped).toContain("90");
  });

  it("leaves host_age below the max unchanged", () => {
    expect(returnHipaaCompliantMetadata("host_age", "40")).toBe("40");
  });

  it("leaves non-age metadata types unchanged", () => {
    expect(returnHipaaCompliantMetadata("sex", "Female")).toBe("Female");
  });
});

describe("formatSendValue", () => {
  it("wraps object values under the location input key", () => {
    const value = { name: "SF", id: 2 };
    expect(formatSendValue(value)).toEqual({
      query_SampleMetadata_metadata_items_location_validated_value_oneOf_1_Input:
        value,
    });
  });

  it("stringifies scalar values under String", () => {
    expect(formatSendValue(5)).toEqual({ String: "5" });
    expect(formatSendValue("hello")).toEqual({ String: "hello" });
  });
});
