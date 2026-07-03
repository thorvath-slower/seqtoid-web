/**
 * Pause/resume coverage for the local upload flow: the ResumableUpload soft-pause primitive and the
 * localStorage persistence that lets a resume survive a reload. Together these exercise the
 * pause -> persist -> resume -> complete path the ticket asks for.
 *
 * The AWS SDK is mocked exactly as in resumableUpload.test.ts so this stays a pure unit test.
 */
jest.mock("@aws-sdk/client-s3", () => {
  class Command {
    input: Record<string, unknown>;
    constructor(input: Record<string, unknown>) {
      this.input = input;
    }
  }
  return {
    PutObjectCommand: class PutObjectCommand extends Command {},
    CreateMultipartUploadCommand: class CreateMultipartUploadCommand extends Command {},
    ListPartsCommand: class ListPartsCommand extends Command {},
    UploadPartCommand: class UploadPartCommand extends Command {},
    CompleteMultipartUploadCommand: class CompleteMultipartUploadCommand extends Command {},
    AbortMultipartUploadCommand: class AbortMultipartUploadCommand extends Command {},
    S3Client: class S3Client {},
  };
});

import {
  CompleteMultipartUploadCommand,
  CreateMultipartUploadCommand,
  ListPartsCommand,
  PutObjectCommand,
  UploadPartCommand,
} from "@aws-sdk/client-s3";
import { ResumableUpload } from "../app/assets/src/components/views/SampleUploadFlow/components/UploadProgressModal/resumableUpload";
import {
  clearUploadResumeState,
  hasResumableUpload,
  loadUploadResumeState,
  saveUploadResumeState,
} from "../app/assets/src/components/views/SampleUploadFlow/components/UploadProgressModal/uploadResumeState";

const PART_SIZE = 1024 * 1024 * 5; // 5 MiB (the minimum multipart part size)

beforeAll(() => {
  if (typeof Blob.prototype.arrayBuffer !== "function") {
    // eslint-disable-next-line no-extend-native, @typescript-eslint/no-explicit-any
    (Blob.prototype as any).arrayBuffer = function (
      this: Blob,
    ): Promise<ArrayBuffer> {
      return Promise.resolve(new ArrayBuffer(this.size));
    };
  }
});

const blobOf = (bytes: number): Blob => new Blob([new Uint8Array(bytes)]);

const baseParams = (body: Blob) => ({
  Bucket: "bucket",
  Key: "samples/1/2/fastqs/x_R1.fastq.gz",
  Body: body,
  ChecksumAlgorithm: "SHA256" as const,
});

// A client that captures the created uploadId and can gate UploadPart so we can pause mid-flight.
function makePausableClient(opts: { blockUploadPart?: Promise<void> } = {}) {
  const calls: string[] = [];
  const listPartsResponses: Array<{ IsTruncated: boolean; Parts: unknown[] }> =
    [];
  let partCounter = 0;
  const send = jest.fn(async (command: { constructor: { name: string } }) => {
    calls.push(command.constructor.name);
    if (command instanceof PutObjectCommand) return { ETag: '"put-etag"' };
    if (command instanceof CreateMultipartUploadCommand) {
      return { UploadId: "upload-123" };
    }
    if (command instanceof ListPartsCommand) {
      return listPartsResponses.shift() ?? { IsTruncated: false, Parts: [] };
    }
    if (command instanceof UploadPartCommand) {
      if (opts.blockUploadPart) await opts.blockUploadPart;
      partCounter += 1;
      return { ETag: `"part-etag-${partCounter}"` };
    }
    if (command instanceof CompleteMultipartUploadCommand) {
      return { Location: "https://s3/done" };
    }
    throw new Error(`Unexpected command: ${command.constructor.name}`);
  });
  return {
    client: { send } as never,
    calls,
    listPartsResponses,
  };
}

describe("ResumableUpload pause", () => {
  it("pauses without completing, leaving the multipart upload on S3, and emits the uploadId to persist", async () => {
    // Gate UploadPart forever so the upload is genuinely mid-flight when we pause.
    const neverResolves = new Promise<void>(() => undefined);
    const { client, calls } = makePausableClient({
      blockUploadPart: neverResolves,
    });

    let persistedUploadId: string | null = null;
    const upload = new ResumableUpload({
      client,
      params: baseParams(blobOf(PART_SIZE * 2)),
      leavePartsOnError: true,
    });
    upload.onCreatedMultipartUpload(id => (persistedUploadId = id));

    const donePromise = upload.done();
    // Let the worker create the multipart upload and reach the (blocked) UploadPart.
    await new Promise(resolve => setTimeout(resolve, 0));

    await upload.pause();

    await expect(donePromise).rejects.toMatchObject({ name: "PauseError" });
    expect(upload.isPaused()).toBe(true);
    // Created but never completed -> parts remain on S3 for a resume.
    expect(calls).toContain("CreateMultipartUploadCommand");
    expect(calls).not.toContain("CompleteMultipartUploadCommand");
    // The uploadId needed to resume was surfaced for persistence.
    expect(persistedUploadId).toBe("upload-123");
  });

  it("resumes from the persisted uploadId (ListParts, skip completed) and completes", async () => {
    const { client, calls, listPartsResponses } = makePausableClient();
    // Report part 1 as already uploaded so resume must skip it via ListParts.
    listPartsResponses.push({
      IsTruncated: false,
      Parts: [{ PartNumber: 1, ETag: '"part-etag-1"' }],
    });

    const resumed = new ResumableUpload({
      client,
      params: baseParams(blobOf(PART_SIZE * 2)),
      uploadId: "upload-123", // the persisted id from the paused session
    });

    const result = await resumed.done();

    expect(calls).toContain("ListPartsCommand");
    // Resume reuses the existing upload rather than creating a new one, and finalizes it.
    expect(calls).not.toContain("CreateMultipartUploadCommand");
    expect(calls).toContain("CompleteMultipartUploadCommand");
    expect((result as { Location?: string }).Location).toBe("https://s3/done");
  });
});

describe("uploadResumeState persistence (pause -> reload -> resume)", () => {
  const PROJECT_ID = 42;

  beforeEach(() => window.localStorage.clear());

  it("round-trips the uploadIds and completed files needed to resume after a reload", () => {
    saveUploadResumeState(PROJECT_ID, {
      sampleFileUploadIds: { "samples/1/a_R1.fastq.gz": "upload-123" },
      sampleFileCompleted: { "samples/1/a_R2.fastq.gz": true },
    });

    const loaded = loadUploadResumeState(PROJECT_ID);
    expect(loaded?.sampleFileUploadIds).toEqual({
      "samples/1/a_R1.fastq.gz": "upload-123",
    });
    expect(loaded?.sampleFileCompleted).toEqual({
      "samples/1/a_R2.fastq.gz": true,
    });
    expect(hasResumableUpload(loaded)).toBe(true);
  });

  it("scopes state per project and clears it on completion", () => {
    saveUploadResumeState(PROJECT_ID, {
      sampleFileUploadIds: { k: "upload-1" },
      sampleFileCompleted: {},
    });
    // A different project is unaffected.
    expect(loadUploadResumeState(99)).toBeNull();

    clearUploadResumeState(PROJECT_ID);
    expect(loadUploadResumeState(PROJECT_ID)).toBeNull();
    expect(hasResumableUpload(null)).toBe(false);
  });
});
