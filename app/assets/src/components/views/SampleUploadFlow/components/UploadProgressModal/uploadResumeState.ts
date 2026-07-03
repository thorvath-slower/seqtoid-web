/**
 * uploadResumeState — localStorage persistence of the resume state for a paused local upload.
 *
 * ResumableUpload already knows how to resume a multipart upload from a saved `uploadId` (it
 * paginates ListParts and skips completed parts). The missing piece for a user-visible pause/resume
 * that survives a page reload is durably storing, per file, the multipart `uploadId` (and which
 * files already finished), so a fresh page load can re-instantiate ResumableUpload with that id.
 *
 * This is deliberately client-only: the server contract is unchanged (no uploadId column on the
 * sample record). Persisting server-side would let a resume survive a different browser/device and
 * is the natural follow-up — see the ticket. Keyed by project so concurrent uploads to different
 * projects don't clobber each other.
 */

export interface UploadResumeState {
  // s3Key -> multipart uploadId for in-flight (paused) files.
  sampleFileUploadIds: Record<string, string>;
  // s3Key -> true for files that finished uploading (so resume skips them).
  sampleFileCompleted: Record<string, boolean>;
  // Wall-clock ms of the last write, for staleness display / future GC.
  updatedAt: number;
}

const KEY_PREFIX = "czid-upload-resume:";

const storageKey = (projectId: number | string): string =>
  `${KEY_PREFIX}${projectId}`;

// localStorage can throw (private mode, quota, disabled); resume-persistence is best-effort, so
// every access is guarded and failures degrade to "no persisted state" rather than breaking upload.
export const saveUploadResumeState = (
  projectId: number | string,
  state: Omit<UploadResumeState, "updatedAt">,
): void => {
  try {
    const payload: UploadResumeState = { ...state, updatedAt: Date.now() };
    window.localStorage.setItem(storageKey(projectId), JSON.stringify(payload));
  } catch {
    // best-effort: ignore
  }
};

export const loadUploadResumeState = (
  projectId: number | string,
): UploadResumeState | null => {
  try {
    const raw = window.localStorage.getItem(storageKey(projectId));
    if (!raw) return null;
    const parsed = JSON.parse(raw) as UploadResumeState;
    if (
      !parsed ||
      typeof parsed !== "object" ||
      typeof parsed.sampleFileUploadIds !== "object"
    ) {
      return null;
    }
    return {
      sampleFileUploadIds: parsed.sampleFileUploadIds ?? {},
      sampleFileCompleted: parsed.sampleFileCompleted ?? {},
      updatedAt: parsed.updatedAt ?? 0,
    };
  } catch {
    return null;
  }
};

export const clearUploadResumeState = (
  projectId: number | string,
): void => {
  try {
    window.localStorage.removeItem(storageKey(projectId));
  } catch {
    // best-effort: ignore
  }
};

// True if there is any in-flight (resumable) uploadId still recorded — i.e. an interrupted upload
// that a resume could pick up.
export const hasResumableUpload = (
  state: UploadResumeState | null,
): boolean => !!state && Object.keys(state.sampleFileUploadIds).length > 0;
