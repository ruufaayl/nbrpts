export type QueryLogRow = {
  id: number;
  ran_at: string;
  caller: string;
  sql_text: string;
  params: unknown | null;
  duration_ms: string | null;
  rows_returned: number | null;
  plan: unknown | null;
};
