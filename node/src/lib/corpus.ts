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

type Literal = string | number | boolean;

function lit(v: Literal): string {
  if (typeof v === "string") return `'${v.replaceAll("'", "''")}'`;
  if (typeof v === "boolean") return v ? "1" : "0";
  return String(v);
}

function insert(table: string, row: Record<string, Literal>): string {
  const values = Object.values(row).map(lit).join(", ");
  return `INSERT INTO ${table} (${Object.keys(row).join(", ")}) VALUES (${values});`;
}

// SQL that loads a corpus into the 0001_init schema; `npm run db:seed` runs it against local D1.
export function seedSql(corpus: Corpus): string {
  return [
    ...corpus.hubs.map((hub) =>
      insert("hub", { ...hub, is_home: hub.id === corpus.home_hub_id, fictional: corpus.fictional }),
    ),
    ...corpus.assets.map((asset) => insert("hub_asset", { ...asset })),
    ...corpus.roles.map((role) => insert("role", { ...role })),
    ...corpus.task_templates.map((task) => insert("task_template", { ...task })),
  ].join("\n");
}
