import { afterEach, describe, expect, it } from "vitest";
import {
  StubMunicipalitySubmissionAdapter,
  getMunicipalitySubmissionAdapter,
  setMunicipalitySubmissionAdapter,
  type MunicipalitySubmissionAdapter,
  type SubmissionResult,
} from "./municipality-submission-adapter.js";

describe("submission adapter selection — swappable boundary", () => {
  afterEach(() => {
    setMunicipalitySubmissionAdapter(new StubMunicipalitySubmissionAdapter());
  });

  it("defaults to the stub (local ELM-ref minting) impl", () => {
    expect(getMunicipalitySubmissionAdapter()).toBeInstanceOf(
      StubMunicipalitySubmissionAdapter,
    );
  });

  it("setMunicipalitySubmissionAdapter swaps in a custom CRM impl, round-trips its ref", async () => {
    const expected: SubmissionResult = { refNumber: "ELM-2026-999999" };
    const calls: string[] = [];
    const custom: MunicipalitySubmissionAdapter = {
      async submit(req) {
        calls.push(req.objectionId);
        return expected;
      },
    };
    setMunicipalitySubmissionAdapter(custom);

    expect(getMunicipalitySubmissionAdapter()).toBe(custom);
    const result = await getMunicipalitySubmissionAdapter().submit({
      objectionId: "obj_1",
      userId: "usr_1",
    });
    expect(result).toEqual(expected);
    expect(calls).toEqual(["obj_1"]);
  });
});
