export const LIST_TABLES_SQL = `
  select table_schema, table_name
  from information_schema.tables
  where table_type = 'BASE TABLE'
    and table_schema not in ('pg_catalog','information_schema','auth','storage','vault','cron',
                             'graphql','graphql_public','realtime','supabase_functions',
                             'supabase_migrations','extensions','pgsodium','pgsodium_masks','net')
  order by table_schema, table_name
`;

export interface TableOut { schema: string; table: string; }

export function parseTables(rows: Array<{ table_schema: string; table_name: string }>): TableOut[] {
  return rows.map((r) => ({ schema: r.table_schema, table: r.table_name }));
}
