import type { RecordStatus } from "@/lib/domain/types";

export type HospitalDashboard = {
  hospital: {
    hospital_id: string;
    hospital_name: string;
    district: string;
    province: string;
    hrn: string;
  };
  records_by_status: Partial<Record<RecordStatus, number>>;
  recent_submissions: HospitalRecentSubmission[];
  children_registered: number;
  bforms_ready: number;
  pending_offline: number;
  generated_at: string;
  error?: string;
};

export type HospitalRecentSubmission = {
  birth_record_id: string;
  brn: string;
  status: RecordStatus;
  submitted_at: string;
  mother_name: string;
  child_name: string | null;
  remarks: string | null;
};

export type HospitalSubmission = {
  birth_record_id: string;
  brn: string;
  status: RecordStatus;
  submitted_at: string;
  birth_datetime: string;
  child_full_name: string | null;
  child_gender: "MALE" | "FEMALE" | "OTHER";
  birth_weight_kg: number | string;
  mother_name: string;
  mother_cnic: string | null;
  attending_doctor: string;
  remarks: string | null;
  has_child: boolean;
  cnin: string | null;
};

export type SubmitFormData = {
  mother_cnic: string;
  mother_full_name: string;
  mother_dob: string;
  mother_contact: string;
  mother_address: string;
  mother_province: "PUNJAB" | "SINDH" | "KPK" | "BALOCHISTAN" | "GB" | "AJK" | "ICT";
  mother_district: string;
  mother_blood_group: string;
  father_cnic: string;
  father_full_name: string;
  father_dob: string;
  father_contact: string;
  attending_doctor: string;
  doctor_license_no: string;
  birth_datetime: string;
  delivery_type: "NORMAL" | "C_SECTION" | "ASSISTED" | "OTHER";
  birth_weight_kg: string;
  birth_outcome: "LIVE_BIRTH" | "STILLBORN" | "DECEASED_AFTER_BIRTH";
  child_gender: "MALE" | "FEMALE" | "OTHER";
  child_full_name: string;
  remarks: string;
};
