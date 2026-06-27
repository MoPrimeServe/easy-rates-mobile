// Municipality submission (outbound — objection → municipal CRM)
export {
  StubMunicipalitySubmissionAdapter,
  nextElmRefNumber,
  getMunicipalitySubmissionAdapter,
  setMunicipalitySubmissionAdapter,
} from "./municipality-submission-adapter.js";
export type {
  MunicipalitySubmissionAdapter,
  SubmissionRequest,
  SubmissionResult,
} from "./municipality-submission-adapter.js";

// Municipality response (inbound — municipal CRM → objection status ingestion)
export {
  OBJECTION_STATUSES,
  isTerminal,
  classifyTransition,
  StateMachineMunicipalityResponseAdapter,
  getMunicipalityResponseAdapter,
  setMunicipalityResponseAdapter,
} from "./municipality-response-adapter.js";
export type {
  TransitionDecision,
  IncomingMunicipalityResponse,
  MunicipalityResponseAdapter,
} from "./municipality-response-adapter.js";
