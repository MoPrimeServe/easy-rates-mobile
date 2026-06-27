import { afterEach, describe, expect, it } from "vitest";
import {
  StateMachineMunicipalityResponseAdapter,
  classifyTransition,
  getMunicipalityResponseAdapter,
  isTerminal,
  setMunicipalityResponseAdapter,
  type IncomingMunicipalityResponse,
  type MunicipalityResponseAdapter,
  type TransitionDecision,
} from "./municipality-response-adapter.js";

const incoming = (
  status: IncomingMunicipalityResponse["status"],
): IncomingMunicipalityResponse => ({
  refNumber: "ELM-2026-000001",
  status,
  note: "A sufficiently long municipal note.",
  adjustedAmount: null,
});

describe("StateMachineMunicipalityResponseAdapter — default impl round-trips the state machine", () => {
  const adapter = new StateMachineMunicipalityResponseAdapter();

  it("applies legal non-terminal transitions", () => {
    expect(adapter.classify("UNDER_REVIEW", incoming("UPHELD")).kind).toBe("apply");
    expect(
      adapter.classify("MORE_INFO_REQUESTED", incoming("UNDER_REVIEW")).kind,
    ).toBe("apply");
  });

  it("rejects re-opening a terminal objection (409 terminal)", () => {
    expect(adapter.classify("UPHELD", incoming("UNDER_REVIEW")).kind).toBe(
      "terminal",
    );
  });

  it("rejects a no-op transition (422 illegal)", () => {
    expect(adapter.classify("UNDER_REVIEW", incoming("UNDER_REVIEW")).kind).toBe(
      "illegal",
    );
  });

  it("matches the underlying classifyTransition pure function", () => {
    expect(adapter.classify("UNDER_REVIEW", incoming("REJECTED"))).toEqual(
      classifyTransition("UNDER_REVIEW", "REJECTED"),
    );
  });

  it("isTerminal flags only UPHELD and REJECTED", () => {
    expect(isTerminal("UPHELD")).toBe(true);
    expect(isTerminal("REJECTED")).toBe(true);
    expect(isTerminal("UNDER_REVIEW")).toBe(false);
  });
});

describe("response adapter selection — swappable boundary", () => {
  afterEach(() => {
    setMunicipalityResponseAdapter(
      new StateMachineMunicipalityResponseAdapter(),
    );
  });

  it("defaults to the state-machine adapter", () => {
    expect(getMunicipalityResponseAdapter()).toBeInstanceOf(
      StateMachineMunicipalityResponseAdapter,
    );
  });

  it("setMunicipalityResponseAdapter swaps in a custom impl", () => {
    const fixed: TransitionDecision = { kind: "apply" };
    const custom: MunicipalityResponseAdapter = { classify: () => fixed };
    setMunicipalityResponseAdapter(custom);
    expect(getMunicipalityResponseAdapter()).toBe(custom);
    // Even a terminal current returns the custom verdict once swapped.
    expect(
      getMunicipalityResponseAdapter().classify("UPHELD", incoming("REJECTED")),
    ).toBe(fixed);
  });
});
