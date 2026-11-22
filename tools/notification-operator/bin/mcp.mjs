import {BrokerConnector} from '../src/broker.mjs';
import {privateDirectory} from '../src/private_state.mjs';
import {serveMcp,unconfiguredClient} from '../src/mcp.mjs';

let client = unconfiguredClient();
try {
  const args = process.argv.slice(2);
  if (args.length) {
    const [stateOption, stateDir, descriptorOption, descriptorSha256] = args;
    if (args.length !== 4 || stateOption !== '--state-dir' || descriptorOption !== '--descriptor-sha256') {
      throw new Error('invalid_arguments');
    }
    await privateDirectory(stateDir);
    process.chdir(stateDir);
    client = new BrokerConnector({stateDir, descriptorSha256});
    await client.connect();
  }
  serveMcp({client});
} catch {
  client.close();
  process.stderr.write('Collect operator broker admission failed. No authentication or fallback was attempted.\n');
  process.exitCode = 1;
}
