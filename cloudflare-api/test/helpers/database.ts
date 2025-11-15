import { env } from 'cloudflare:test';

let schemaSqlPromise: Promise<string> | null = null;

async function loadSchema(): Promise<string> {
  if (!schemaSqlPromise) {
    schemaSqlPromise = import('../../migrations/0001_initial_schema.sql?raw').then(
      module => module.default
    );
  }
  return schemaSqlPromise!;
}

async function execOnDatabases(sql: string): Promise<void> {
  const databases = [env.DB, env.TEST_DB].filter(Boolean) as D1Database[];

  const sanitizedSql = sql
    .replace(/\s*--.*$/gm, '')
    .split('\n')
    .map(line => line.trim())
    .filter(line => line.length > 0)
    .join(' ');

  const statements = sanitizedSql
    .split(';')
    .map(stmt => stmt.trim())
    .filter(stmt => stmt.length > 0);

  await Promise.all(databases.map(async db => {
    for (const statement of statements) {
      await db.exec(statement);
    }
  }));
}

export async function applyMigrations(): Promise<void> {
  const sql = await loadSchema();
  await execOnDatabases(sql);
}

export async function resetDatabase(): Promise<void> {
  await applyMigrations();
  const truncateSql = [
    'DELETE FROM reviews;',
    'DELETE FROM purchases;',
    'DELETE FROM scripts;',
    'DELETE FROM users;'
  ].join('\n');

  await execOnDatabases(truncateSql);
}

export async function dropCoreTables(): Promise<void> {
  const dropSql = [
    'DROP TABLE IF EXISTS reviews;',
    'DROP TABLE IF EXISTS purchases;',
    'DROP TABLE IF EXISTS scripts;',
    'DROP TABLE IF EXISTS users;'
  ].join('\n');

  await execOnDatabases(dropSql);
}
