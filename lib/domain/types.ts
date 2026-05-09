export type RecordStatus =
  | "PENDING"
  | "FLAGGED"
  | "VERIFIED"
  | "REJECTED"
  | "AMENDED";

export type PipelineSummary = {
  records_by_status: Partial<Record<RecordStatus, number>>;
  children: number;
  bforms_total: number;
  bforms_authorized: number;
  bforms_pending: number;
  notifications_queued: number;
  notifications_sent: number;
  audit_entries: number;
  verification_logs: number;
  generated_at: string;
};

export type PendingBirthOption = {
  birth_record_id: string;
  brn: string;
  mother_name: string;
  hospital_name: string;
  status: RecordStatus;
  submitted_at: string;
};

export type PendingBformOption = {
  bform_id: string;
  bform_number: string;
  child_name: string;
  child_id: string;
  authorized_at: string | null;
};

export type CurrentBformOption = {
  child_id: string;
  child_name: string;
  bform_number: string;
  version: number;
};

export type AuditEntry = {
  audit_id: string;
  actor_type: string;
  actor_id: string | null;
  action_type: string;
  table_affected: string;
  record_id: string | null;
  action_datetime: string;
  description: string | null;
};
