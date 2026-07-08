// #586 (epic #462) coverage: pipeline_versions.isPipelineVersionAtLeast is a
// semver-ish comparator with nested major/minor/patch/prerelease branches and
// alpha/beta handling -- a branch goldmine gating feature availability. Pure.
import {
  ACCESSION_COVERAGE_STATS_FEATURE,
  ASSEMBLY_FEATURE,
  isAmrGeneLevelContigDownloadAvailable,
  isAmrGeneLevelDownloadAvailable,
  isPipelineFeatureAvailable,
  isPipelineVersionAtLeast,
  MINIMUM_VERSIONS,
} from "../app/assets/src/components/utils/pipeline_versions";

describe("isPipelineVersionAtLeast", () => {
  it("returns false for an empty/falsy pipeline version", () => {
    expect(isPipelineVersionAtLeast("", "1.0.0")).toBe(false);
  });

  it("returns true for equal versions", () => {
    expect(isPipelineVersionAtLeast("1.0.0", "1.0.0")).toBe(true);
  });

  it("returns false when patch is lower", () => {
    expect(isPipelineVersionAtLeast("1.0.0", "1.0.1")).toBe(false);
  });

  it("returns true when minor is higher", () => {
    expect(isPipelineVersionAtLeast("1.2.0", "1.0.0")).toBe(true);
  });

  it("returns true when major is higher", () => {
    expect(isPipelineVersionAtLeast("2.0.0", "1.9.9")).toBe(true);
  });

  // NOTE: the prerelease (alpha/beta) comparison is effectively dead code: the
  // patch-level `>=` short-circuits and returns true whenever major/minor/patch
  // are equal, before parts[3] is ever compared. So a prerelease of an otherwise
  // equal version reads as "at least" the release, contrary to the source
  // docstring's aspirational examples. These cases pin the ACTUAL behavior.
  it("treats a beta prerelease of an equal version as at least the release (patch >= short-circuit)", () => {
    expect(isPipelineVersionAtLeast("1.0.0-beta", "1.0.0")).toBe(true);
  });

  it("treats a release as at least a beta of the same version", () => {
    expect(isPipelineVersionAtLeast("1.0.0", "1.0.0-beta")).toBe(true);
  });

  it("reads alpha as at least beta at the same major/minor/patch (unreachable prerelease branch)", () => {
    expect(isPipelineVersionAtLeast("1.0.0-alpha", "1.0.0-beta")).toBe(true);
  });

  it("does apply prerelease weighting when it lands in the major slot", () => {
    // Here alpha (-2) vs beta (-1) is compared as the major field, which is
    // reachable, so alpha < beta -> false.
    expect(isPipelineVersionAtLeast("alpha", "beta")).toBe(false);
    expect(isPipelineVersionAtLeast("beta", "alpha")).toBe(true);
  });

  it("accepts dash-separated version fields", () => {
    expect(isPipelineVersionAtLeast("1-2-0", "1-0-0")).toBe(true);
  });
});

describe("isPipelineFeatureAvailable", () => {
  it("returns true when the pipeline meets the feature minimum", () => {
    // ASSEMBLY_FEATURE minimum is 3.1.
    expect(isPipelineFeatureAvailable(ASSEMBLY_FEATURE, "3.1")).toBe(true);
    expect(MINIMUM_VERSIONS[ASSEMBLY_FEATURE]).toBe("3.1");
  });

  it("returns false when the pipeline is below the feature minimum", () => {
    expect(
      isPipelineFeatureAvailable(ACCESSION_COVERAGE_STATS_FEATURE, "5.9"),
    ).toBe(false);
  });
});

describe("AMR gene-level download availability", () => {
  it("gates gene-level downloads at 1.1.0", () => {
    expect(isAmrGeneLevelDownloadAvailable("1.1.0")).toBe(true);
    expect(isAmrGeneLevelDownloadAvailable("1.0.9")).toBe(false);
  });

  it("gates gene-level contig downloads at 1.2.14", () => {
    expect(isAmrGeneLevelContigDownloadAvailable("1.2.14")).toBe(true);
    expect(isAmrGeneLevelContigDownloadAvailable("1.2.13")).toBe(false);
  });
});
