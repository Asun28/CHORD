export interface Hub { id: string; name: string; suburb: string; address: string }
export interface Asset { id: string; hub_id: string; kind: string; name: string; sensitivity: "public" | "restricted" }
export interface Role { code: string; name: string; description: string; priority_rank: number; source_ref: string }
export interface TaskTemplate { id: string; role_code: string; phase: string; text: string; source_ref: string }
export interface Corpus {
  fictional: boolean;
  home_hub_id: string;
  hubs: Hub[];
  assets: Asset[];
  roles: Role[];
  task_templates: TaskTemplate[];
}

// The part of the D1 binding API this node uses.
export interface SqlDb {
  prepare(sql: string): {
    bind(...values: unknown[]): {
      first<T = Record<string, unknown>>(): Promise<T | null>;
      all<T = Record<string, unknown>>(): Promise<{ results: T[] }>;
    };
  };
}

export function seedSql(corpus: Corpus): string {
  void corpus;
  return "";
}
