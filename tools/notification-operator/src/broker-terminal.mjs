import { open } from 'node:fs/promises';
import { isatty, ReadStream, WriteStream } from 'node:tty';

// A physical terminal keeps email codes out of the tool protocol and piped input.
export async function openOperatorTerminal(lifetime) {
  const handle = await open('/dev/tty', 'r+');
  if (!isatty(handle.fd)) {
    await handle.close();
    throw new Error('interactive_terminal_required');
  }
  const reader = new ReadStream(handle.fd, { autoClose: false });
  const writer = new WriteStream(handle.fd, { autoClose: false });

  async function prompt(label, { secret = false, signal = lifetime } = {}) {
    if (signal.aborted) throw new Error('cancelled');
    writer.write(label);
    reader.setRawMode(true);
    reader.resume();
    let text = '';

    return new Promise((resolve, reject) => {
      function finish() {
        reader.off('data', read);
        signal.removeEventListener('abort', cancel);
        reader.setRawMode(false);
        reader.pause();
      }

      function cancel() {
        finish();
        reject(new Error('cancelled'));
      }

      function read(chunk) {
        for (const character of chunk.toString('utf8')) {
          if (character === '\x03') return cancel();
          if (character === '\r' || character === '\n') {
            finish();
            writer.write('\n');
            resolve(text);
            return;
          }
          if (character === '\x7f') {
            text = text.slice(0, -1);
            if (!secret) writer.write('\b \b');
          } else if (character >= ' ' && text.length < 512) {
            text += character;
            if (!secret) writer.write(character);
          }
        }
      }

      reader.on('data', read);
      signal.addEventListener('abort', cancel, { once: true });
    });
  }

  return {
    prompt,
    write: text => writer.write(text),
    async close() {
      reader.destroy();
      writer.destroy();
      await handle.close().catch(() => {});
    },
  };
}
