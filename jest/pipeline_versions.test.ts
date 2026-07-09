// CZID-462 (#586) coverage: app/assets/src/components/utils/pipeline_versions.ts
import {
  ASSEMBLY_FEATURE,
  isAmrGeneLevelContigDownloadAvailable,
  isAmrGeneLevelDownloadAvailable,
  isPipelineFeatureAvailable,
  isPipelineVersionAtLeast,
} from "../app/assets/src/components/utils/pipeline_versions";

describe("pipeline_versions.ts", () => {
  describe("isPipelineVersionAtLeast", () => {
    it("returns false when pipelineVersion is empty/undefined", () => {
      expect(isPipelineVersionAtLeast("", "1.0.0")).toBe(false);
      // @ts-expect-error deliberately passing undefined to hit the guard
      expect(isPipelineVersionAtLeast(undefined, "1.0.0")).toBe(false);
    });
    it("handles equal versions", () => {
      expect(isPipelineVersionAtLeast("1.0.0", "1.0.0")).toBe(true);
    });
    it("compares by major version", () => {
      expect(isPipelineVersionAtLeast("2.0.0", "1.9.9")).toBe(true);
      expect(isPipelineVersionAtLeast("1.0.0", "2.0.0")).toBe(false);
    });
    it("compares by minor version when major is equal", () => {
      expect(isPipelineVersionAtLeast("1.2.0", "1.0.0")).toBe(true);
      expect(isPipelineVersionAtLeast("1.0.0", "1.2.0")).toBe(false);
    });
    it("compares by patch version when major and minor are equal", () => {
      expect(isPipelineVersionAtLeast("1.0.1", "1.0.0")).toBe(true);
      expect(isPipelineVersionAtLeast("1.0.0", "1.0.1")).toBe(false);
    });
    it("treats equal major.minor.patch as satisfied regardless of prerelease tag", () => {
      // The patch-level check uses >= and short-circuits to true before the
      // prerelease tag is ever compared, so any equal major.minor.patch passes.
      expect(isPipelineVersionAtLeast("1.0.0", "1.0.0-beta")).toBe(true);
      expect(isPipelineVersionAtLeast("1.0.0-beta", "1.0.0")).toBe(true);
      expect(isPipelineVersionAtLeast("1.0.0-alpha", "1.0.0-beta")).toBe(true);
    });
    it("still fails when the patch version is strictly lower", () => {
      expect(isPipelineVersionAtLeast("1.0.0-beta", "1.0.1")).toBe(false);
    });
    it("accepts dash-separated version fields", () => {
      expect(isPipelineVersionAtLeast("1-2-0", "1-0-0")).toBe(true);
    });
  });

  describe("isPipelineFeatureAvailable", () => {
    it("checks the minimum version for a feature", () => {
      expect(isPipelineFeatureAvailable(ASSEMBLY_FEATURE, "3.1")).toBe(true);
      expect(isPipelineFeatureAvailable(ASSEMBLY_FEATURE, "3.0")).toBe(false);
    });
  });

  describe("AMR gene-level download helpers", () => {
    it("gates gene-level downloads at 1.1.0", () => {
      expect(isAmrGeneLevelDownloadAvailable("1.1.0")).toBe(true);
      expect(isAmrGeneLevelDownloadAvailable("1.0.0")).toBe(false);
    });
    it("gates gene-level contig downloads at 1.2.14", () => {
      expect(isAmrGeneLevelContigDownloadAvailable("1.2.14")).toBe(true);
      expect(isAmrGeneLevelContigDownloadAvailable("1.2.13")).toBe(false);
    });
  });
});
