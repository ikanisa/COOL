import {BrokerConnector} from '../src/broker.mjs';
import {privateDirectory} from '../src/private_state.mjs';
import {serveMcp,unconfiguredClient} from '../src/mcp.mjs';

let client=unconfiguredClient();
try {
  const args=process.argv.slice(2);
  if(args.length) {
    if(args.length!==4||args[0]!=='--state-dir'||args[2]!=='--descriptor-sha256')throw new Error('invalid_arguments');
    await privateDirectory(args[1]);process.chdir(args[1]);client=new BrokerConnector({stateDir:args[1],descriptorSha256:args[3]});await client.connect();
  }
  serveMcp({client});
} catch {client.close();process.stderr.write('Collect operator broker admission failed. No authentication or fallback was attempted.\n');process.exitCode=1;}
