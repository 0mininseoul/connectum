export function quoteIdent(name: string): string {
  return `"${name.replace(/"/g, '""')}"`;
}
export function quoteLiteral(value: string): string {
  return `'${value.replace(/'/g, "''")}'`;
}
export interface SelectArgs {
  schema: string; table: string; cursorColumn: string; cursorValue?: string; limit: number;
}
export function buildSelectSQL(a: SelectArgs): string {
  const tbl = `${quoteIdent(a.schema)}.${quoteIdent(a.table)}`;
  const col = quoteIdent(a.cursorColumn);
  const where = a.cursorValue != null ? ` where ${col} > ${quoteLiteral(a.cursorValue)}` : "";
  return `select * from ${tbl}${where} order by ${col} asc limit ${a.limit}`;
}
