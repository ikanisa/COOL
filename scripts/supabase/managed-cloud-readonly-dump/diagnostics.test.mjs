import test from 'node:test';
import assert from 'node:assert/strict';
import {cleanDiagnostic,decodeDiagnostics,normalizedSignal,MAX_DIAGNOSTIC_BYTES} from './diagnostics.mjs';
test('only fixed phase and bounded child facts survive diagnostic decoding',()=>{
 const wire=Buffer.from('{"phase":"dump_started"}\n{"phase":"dump_process_closed","exitCode":1,"signal":null,"stderrBytes":123}\n');
 assert.deepEqual(decodeDiagnostics(wire),[{phase:'dump_started'},{phase:'dump_process_closed',exitCode:1,signal:null,stderrBytes:123}]);
 assert.equal(normalizedSignal('unexpected sensitive text'),'OTHER');assert.equal(cleanDiagnostic({phase:'dump_started',sql:'secret'}),null);
 for(const text of ['{"phase":"dump_started","stderr":"secret"}\n','{"phase":"not_allowed"}\n','{"phase":"dump_process_closed","exitCode":1,"signal":"secret","stderrBytes":3}\n','{"phase":"dump_started"}'])assert.deepEqual(decodeDiagnostics(Buffer.from(text)),[]);
 assert.deepEqual(decodeDiagnostics(Buffer.from('{"phase":"dump_started"}\npartial')),[{phase:'dump_started'}]);
 assert.deepEqual(decodeDiagnostics(Buffer.alloc(MAX_DIAGNOSTIC_BYTES+1)),[]);
});
