const MAX_FRAME = 64 * 1024;

export function createFrameReader(receive, reject, {maxFrameBytes = MAX_FRAME, ignoreEmptyLines = false} = {}) {
  const decoder = new TextDecoder('utf-8', { fatal: true });
  let input = Buffer.alloc(0);
  let discarding = false;
  let stopped = false;

  function decode(bytes) {
    let message;
    try {
      message = JSON.parse(decoder.decode(bytes));
    } catch {
      reject('Invalid UTF-8 JSON message.', 'parse');
      return;
    }
    receive(message);
  }

  function read(chunk) {
    if (stopped) return;
    const bytes = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    let start = 0;
    for (let end = bytes.indexOf(10, start); end !== -1; end = bytes.indexOf(10, start)) {
      const part = bytes.subarray(start, end);
      start = end + 1;
      const size = input.length + part.length;
      if (!discarding && size <= maxFrameBytes) {
        if (size || !ignoreEmptyLines) decode(Buffer.concat([input, part]));
      } else if (!discarding && oversized()) {
        return;
      }
      input = Buffer.alloc(0);
      discarding = false;
    }

    if (discarding) return;
    const tail = bytes.subarray(start);
    if (input.length + tail.length > maxFrameBytes) {
      oversized();
      input = Buffer.alloc(0);
      discarding = true;
    } else if (tail.length > 0) {
      input = Buffer.concat([input, tail]);
    }
  }

  function end() {
    if (input.length && !discarding && !stopped) return reject('An MCP message must end with a newline.', 'incomplete');
  }

  function oversized() {
    stopped = reject('Message exceeds the supported size.', 'oversized') === false;
    return stopped;
  }

  return { read, end };
}
