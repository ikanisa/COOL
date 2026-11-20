// A successful Node process can still contain skipped or omitted test cases.
export function assertCompleteTap(output,expected){
 if(typeof output!=='string'||!Array.isArray(expected)||expected.length===0||new Set(expected).size!==expected.length)throw Error('OWNED_PG_TEST_COVERAGE_UNCONFIRMED');
 const passed=[...output.matchAll(/^\s*ok [0-9]+ - (.+)$/gm)].map(match=>match[1]);
 const summaries=[...output.matchAll(/^# (tests|pass|fail|cancelled|skipped|todo) ([0-9]+)$/gm)];
 const counts=Object.fromEntries(summaries.map(match=>[match[1],Number(match[2])]));
 if(summaries.length!==6||counts.tests!==expected.length||counts.pass!==expected.length||
  counts.fail!==0||counts.cancelled!==0||counts.skipped!==0||counts.todo!==0||passed.length!==expected.length||
  new Set(passed).size!==passed.length||expected.some(name=>!passed.includes(name)))throw Error('OWNED_PG_TEST_COVERAGE_UNCONFIRMED');
 return counts.pass;
}
