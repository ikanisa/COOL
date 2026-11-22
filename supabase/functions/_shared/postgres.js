import {PostgresTransactions} from './postgres-transactions.js';
import {compileSql} from './postgres-compatibility-sql.js';
import {COLLECT_MUTATION_LOCK} from './postgres-mutation-lock.js';

// Existing consumers of the D1 compatibility entrypoint keep their exports.
export {connection,fenceConnection,leaseOwnedControlPool} from './postgres-connections.js';
export {compileSql};

class Statement {
  constructor(db, sql, values = []) { this.db=db; this.sql=sql; this.values=values; }
  bind(...values) { return new Statement(this.db,this.sql,values); }
  async all() { return this.db.execute(this); }
  async first(column) { const row=(await this.all()).results[0] ?? null; return column && row ? row[column] : row; }
  async run() { return this.all(); }
  async raw() { return (await this.all()).results.map(Object.values); }
}
export class PostgresDatabase extends PostgresTransactions {
  prepare(text) { return new Statement(this,text); }
  withSession() { return this; }
  async statement(tx, statement) {
    const q=compileSql(statement.sql,statement.values);
    let result;try{result=await tx.unsafe(q.text,q.values);}catch(error){error.collectSql=q.text;throw error;}
    await tx`select pg_catalog.set_config('collect.last_changes',${String(result.count ?? result.length)},true)`;
    return {success:true,results:Array.from(result),meta:{changes:result.count ?? result.length}};
  }
  async execute(statement) { return this.transaction(async tx=>{await this.context(tx);return this.statement(tx,statement);}); }
  async batch(statements) {
    return this.transaction(async tx=>{
      await this.context(tx);
      // D1 serialized all mutations. Serialize financial and authority batches
      // until reviewed per-group locking proves equivalent under concurrency.
      await tx.unsafe(`SELECT pg_catalog.pg_advisory_xact_lock(${COLLECT_MUTATION_LOCK}::bigint)`);
      const result=[];for(const s of statements) result.push(await this.statement(tx,s));return result;
    });
  }
  async adminReadBatch(context,check,statements) {
    return this.withLockedReadSnapshot(async tx=>{
      await this.statement(tx,context);
      const authority=await this.statement(tx,check);
      if(authority.results.length!==1||authority.results[0].allowed!==true)throw new Error('admin_account_authority');
      const result=[];
      for(const statement of statements)result.push(await this.statement(tx,statement));
      return result;
    });
  }
  async query(text, values=[]) { return this.execute(this.prepare(text).bind(...values)); }
}
