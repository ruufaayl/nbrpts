import type { RecordStatus } from "@/lib/domain/types";

export type OfficerProfile = {
  officer_id: string;
  employee_no: string;
  full_name: string;
  designation: string;
  office_name: string | null;
  city: string | null;
  province: string | null;
};

export type OfficerCounts = {
  pending: number;
  flagged: number;
  verified_today: number;
  rejected_today: number;
  my_actions_today: number;
  bforms_to_authorize: number;
  children_total: number;
  records_total: number;
};

export type OfficerRecentAction = {
  log_id: string;
  action: string;
  previous_status: RecordStatus;
  new_status: RecordStatus;
  action_datetime: string;
  remarks: string | null;
  brn: string;
  hospital_name: string;
};

export type OfficerOldestPending = {
  birth_record_id: string;
  brn: string;
  status: RecordStatus;
  submitted_at: string;
  attending_doctor: string;
  birth_weight_kg: number | string;
  hospital_name: string;
  district: string;
  mother_name: string;
  age_seconds: number;
};

export type OfficerDashboard = {
  officer: OfficerProfile;
  counts: OfficerCounts;
  recent_actions: OfficerRecentAction[];
  oldest_pending: OfficerOldestPending[];
  generated_at: string;
};

export type AiVerdict = "PASS" | "FLAG" | "REJECT";

export type LatestAiReview = {
  verdict: AiVerdict;
  confidence_score: number | string | null;
  flags_raised: unknown[] | null;
  reviewed_at: string;
} | null;

export type OfficerQueueRow = {
  birth_record_id: string;
  brn: string;
  status: RecordStatus;
  submitted_at: string;
  birth_datetime: string;
  attending_doctor: string;
  doctor_license_no: string;
  delivery_type: string;
  birth_weight_kg: number | string;
  birth_outcome: string;
  child_full_name: string | null;
  child_gender: string | null;
  remarks: string | null;
  hospital_id: string;
  hospital_name: string;
  district: string;
  province: string;
  mother_name: string;
  mother_cnic: string | null;
  father_name: string | null;
  father_cnic: string | null;
  latest_ai_review: LatestAiReview;
  age_seconds: number;
};

export type OfficerQueue = {
  rows: OfficerQueueRow[];
  total: number;
  returned: number;
  status: "all" | "pending" | "flagged";
  generated_at: string;
};

export type RecordDetail = {
  record: {
    birth_record_id: string;
    brn: string;
    status: RecordStatus;
    submitted_at: string;
    birth_datetime: string;
    attending_doctor: string;
    doctor_license_no: string;
    delivery_type: string;
    birth_weight_kg: number | string;
    birth_outcome: string;
    child_full_name: string | null;
    child_gender: string | null;
    remarks: string | null;
    ai_review_result: unknown;
  };
  hospital: {
    hospital_id: string;
    hrn: string;
    hospital_name: string;
    hospital_type: string;
    district: string;
    province: string;
    contact_number: string;
  };
  mother: {
    guardian_id: string;
    cnic: string | null;
    full_name: string;
    date_of_birth: string;
    contact_number: string;
    address: string;
    province: string;
    district: string;
    blood_group: string | null;
  };
  father: {
    guardian_id: string;
    cnic: string | null;
    full_name: string;
    date_of_birth: string;
    contact_number: string;
  } | null;
  child: {
    child_id: string;
    cnin: string;
    full_name: string;
    gender: string;
    date_of_birth: string;
    created_at: string;
  } | null;
  bform: {
    bform_id: string;
    bform_number: string;
    version: number;
    is_current: boolean;
    authorized_at: string | null;
    reissue_reason: string | null;
    issue_date: string;
    issued_by_name: string | null;
  } | null;
  ai_history: Array<{
    review_id: string;
    verdict: AiVerdict;
    confidence_score: number | string | null;
    flags_raised: unknown[] | null;
    reviewed_at: string;
    human_override: boolean;
  }>;
  verification_log: Array<{
    log_id: string;
    action: string;
    previous_status: RecordStatus;
    new_status: RecordStatus;
    action_datetime: string;
    remarks: string | null;
    officer_name: string | null;
    employee_no: string | null;
  }>;
  generated_at: string;
};

export type SearchResult = {
  query: string;
  rows: Array<{
    birth_record_id: string;
    brn: string;
    status: RecordStatus;
    submitted_at: string;
    child_full_name: string | null;
    child_gender: string | null;
    cnin: string | null;
    mother_name: string;
    mother_cnic: string | null;
    hospital_name: string;
    district: string;
    match_field: string;
  }>;
};

export type PopulationStats = {
  by_province: Array<{
    province: string;
    total_births: number;
    verified: number;
    flagged: number;
    pending: number;
  }>;
  by_district: Array<{
    district: string;
    province: string;
    total_births: number;
    hospitals: number;
    verified: number;
  }>;
  by_gender: Record<string, number>;
  by_delivery_type: Record<string, number>;
  top_hospitals: Array<{
    hospital_name: string;
    district: string;
    province: string;
    total_births: number;
    verified_pct: number | string;
  }>;
  totals: {
    records: number;
    children: number;
    hospitals: number;
    parents: number;
    bforms_authorized: number;
  };
  generated_at: string;
};

export type BformsWorkload = {
  to_authorize: Array<{
    bform_id: string;
    bform_number: string;
    version: number;
    created_at: string;
    reissue_reason: string | null;
    child_id: string;
    cnin: string;
    child_name: string;
    date_of_birth: string;
    brn: string;
    hospital_name: string;
    district: string;
    mother_name: string;
    mother_contact: string;
  }>;
  recent_authorized: Array<{
    bform_id: string;
    bform_number: string;
    version: number;
    authorized_at: string;
    reissue_reason: string | null;
    child_id: string;
    cnin: string;
    child_name: string;
    mother_name: string;
    hospital_name: string;
    authorized_by: string | null;
  }>;
  generated_at: string;
};
