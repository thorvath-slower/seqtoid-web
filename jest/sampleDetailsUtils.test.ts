// CZID-586 (#586) frontend coverage: SampleDetailsMode/utils.ts normalizes the
// additional-info blob shown in the sample details sidebar, chiefly formatting
// the upload date. Cover all three branches (missing blob / has date / no date).
import { processAdditionalInfo } from "~/components/common/DetailsSidebar/SampleDetailsMode/utils";

describe("processAdditionalInfo", () => {
  it("returns an empty object when there is no additional info", () => {
    expect(processAdditionalInfo(null)).toEqual({});
    expect(processAdditionalInfo(undefined)).toEqual({});
  });

  it("formats the upload_date to YYYY-MM-DD when present", () => {
    const result = processAdditionalInfo({
      name: "sample-1",
      upload_date: "2026-07-08T13:45:00Z",
    } as any);
    expect(result.upload_date).toBe("2026-07-08");
    // Other fields are preserved.
    expect((result as any).name).toBe("sample-1");
  });

  it("returns the info unchanged when it has no upload_date", () => {
    const info = { name: "no-date" } as any;
    expect(processAdditionalInfo(info)).toBe(info);
  });
});
