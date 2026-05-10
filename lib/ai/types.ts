import type { RecordStatus } from "@/lib/domain/types";

export type AiVerdict = "PASS" | "FLAG" | "REJECT";

export type AiFlag = {
  code: string;
  severity: "reject" | "flag" | "info";
  detail: string;
};

export type AiEngineCounts = {
  pending_to_process: number;
  flagged_records: number;
  reviews_today: number;
  reviews_total: number;
  overrides: number;
};

export type AiRecentReview = {
  review_id: string;
  verdict: AiVerdict;
  confidence_score: number | string | null;
  flags_raised: AiFlag[] | null;
  reviewed_at: string;
  human_override: boolean;
  brn: string;
  record_status: RecordStatus;
  hospital_name: string;
  district: string;
  mother_name: string;
};

export type AiNextPending = {
  birth_record_id: string;
  brn: string;
  submitted_at: string;
  attending_doctor: string;
  birth_weight_kg: number | string;
  delivery_type: string;
  hospital_name: string;
  district: string;
  mother_name: string;
  mother_cnic: string | null;
};

export type AiEngineData = {
  counts: AiEngineCounts;
  verdict_breakdown: Partial<Record<AiVerdict, number>>;
  avg_confidence: Partial<Record<AiVerdict, number | string>>;
  recent_reviews: AiRecentReview[];
  next_pending: AiNextPending[];
  generated_at: string;
};

export type ProcessResult = {
  ok: boolean;
  brn?: string;
  review_id?: string;
  verdict?: AiVerdict;
  confidence?: number | string;
  action?: "AUTO_VERIFIED" | "FLAGGED" | "FLAGGED_LOW_CONFIDENCE" | "AUTO_REJECTED";
  flags?: AiFlag[];
  reasons?: string[];
  duration_ms?: number;
  reason?: string;
  error?: string;
};

export type BatchResult = {
  processed: number;
  passed: number;
  flagged: number;
  rejected: number;
  errors: number;
  duration_ms: number;
  results: ProcessResult[];
};
