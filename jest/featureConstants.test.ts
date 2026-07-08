// #586 (epic #462) coverage: features.ts and resultsFolder.ts export feature-flag
// and results-tree key constants consumed by admin gating and the results folder
// view. Pinning the values guards against accidental rename/regression.
import {
  AMR_DEPRECATED_FEATURE,
  BENCHMARKING_FEATURE,
  EDIT_SNAPSHOT_LINKS_FEATURE,
  SAMPLES_TABLE_METADATA_COLUMNS_ADMIN_FEATURE,
  SORTING_V0_ADMIN_FEATURE,
} from "../app/assets/src/components/utils/features";
import {
  READ_DEDUP_KEYS,
  RESULTS_FOLDER_ROOT_KEY,
  RESULTS_FOLDER_STAGE_KEYS,
  RESULTS_FOLDER_STEP_KEYS,
} from "../app/assets/src/components/utils/resultsFolder";

describe("feature flag constants", () => {
  it("exposes the expected feature flag string identifiers", () => {
    expect(AMR_DEPRECATED_FEATURE).toBe("AMR");
    expect(SORTING_V0_ADMIN_FEATURE).toBe("sorting_v0_admin");
    expect(SAMPLES_TABLE_METADATA_COLUMNS_ADMIN_FEATURE).toBe(
      "samples_table_metadata_columns_admin",
    );
    expect(EDIT_SNAPSHOT_LINKS_FEATURE).toBe("edit_snapshot_links");
    expect(BENCHMARKING_FEATURE).toBe("benchmarking");
  });
});

describe("results folder key constants", () => {
  it("exposes the stage and step key maps", () => {
    expect(RESULTS_FOLDER_STAGE_KEYS.stageNameKey).toBe("name");
    expect(RESULTS_FOLDER_STAGE_KEYS.stepsKey).toBe("steps");
    expect(RESULTS_FOLDER_STEP_KEYS.filesKey).toBe("fileList");
    expect(RESULTS_FOLDER_ROOT_KEY).toBe("displayedData");
  });

  it("lists all backwards-compatible dedup keys", () => {
    expect(READ_DEDUP_KEYS).toContain("runCdHitDup");
    expect(READ_DEDUP_KEYS).toContain("czid_dedup_out");
    expect(READ_DEDUP_KEYS).toContain("runCZIDDedup");
    expect(READ_DEDUP_KEYS).toHaveLength(7);
  });
});
