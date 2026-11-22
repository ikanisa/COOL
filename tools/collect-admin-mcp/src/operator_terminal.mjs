import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { SafeError } from './config.mjs';

export async function secretPrompt(label = 'Password (hidden): ', maximum = 512) {
  return new Promise((resolve, reject) => {
    let value = '';
    process.stderr.write(label);
    process.stdin.setRawMode(true);
    process.stdin.resume();
    function done(error) {
      process.stdin.off('data', onData);
      process.stdin.setRawMode(false);
      process.stdin.pause();
      process.stderr.write('\n');
      if (error) reject(error);
      else resolve(value);
    }
    function onData(data) {
      for (const char of data.toString('utf8')) {
        if (char === '\u0003' || char === '\u0004') return done(new SafeError('cancelled', 'Local sign-in cancelled.'));
        if (char === '\r' || char === '\n') return done();
        if (char === '\u007f' || char === '\b') value = Array.from(value).slice(0, -1).join('');
        else if (char >= ' ' && value.length < maximum) value += char;
      }
    }
    process.stdin.on('data', onData);
  });
}

export function runTerminalCommand(entryUrl, command, fallback) {
  if (!process.argv[1] || pathToFileURL(resolve(process.argv[1])).href !== entryUrl) return;
  command().catch(error => {
    process.stderr.write(`${error instanceof SafeError ? error.message : fallback}\n`);
    process.exitCode = 1;
  });
}
