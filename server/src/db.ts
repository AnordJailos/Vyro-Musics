export interface Db {
  query<T = Record<string, any>>(sql: string, params?: unknown[]): Promise<{ rows: T[] }>;
  exec(sql: string): Promise<void>;
  close(): Promise<void>;
}

export async function pgDb(url: string): Promise<Db> {
  const { default: pg } = await import('pg');
  const pool = new pg.Pool({ connectionString: url, options: '-c timezone=UTC' });
  return {
    query: (sql, params) => pool.query(sql, params as any[]) as any,
    exec: async (sql) => {
      await pool.query(sql);
    },
    close: () => pool.end(),
  };
}

export async function memoryDb(): Promise<Db> {
  const { PGlite } = await import('@electric-sql/pglite');
  const db = new PGlite();
  return {
    query: (sql, params) => db.query(sql, params as any[]) as any,
    exec: async (sql) => {
      await db.exec(sql);
    },
    close: () => db.close(),
  };
}

export function isUniqueViolation(e: unknown): boolean {
  const err = e as { code?: string; message?: string };
  return err?.code === '23505' || /duplicate key|unique constraint/i.test(err?.message ?? '');
}
