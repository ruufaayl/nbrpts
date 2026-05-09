export type SchemaColumn = {
  name: string;
  type: string;
  nullable: boolean;
  default: string | null;
  is_primary_key: boolean;
  is_unique: boolean;
  is_foreign_key: boolean;
  references: { table: string; column: string } | null;
};

export type SchemaTable = {
  name: string;
  comment: string;
  rls_enabled: boolean;
  row_count: number;
  columns: SchemaColumn[];
};

export type SchemaForeignKey = {
  from_table: string;
  from_column: string;
  to_table: string;
  to_column: string;
};

export type SchemaPayload = {
  tables: SchemaTable[];
  foreign_keys: SchemaForeignKey[];
  generated_at: string;
};
