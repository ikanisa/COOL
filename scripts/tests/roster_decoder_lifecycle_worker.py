"""Owned child used only by the host lifecycle controls; never a decoder."""
import json
import os
from pathlib import Path
import subprocess
import sys
import threading
sys.path.insert(0, str(Path(__file__).resolve().parent))
from roster_decoder_lifecycle_support import load_lifecycle


directory = Path(sys.argv[1])
namespace = load_lifecycle()
Handler = namespace["Handler"]
BoundedServer = namespace["BoundedServer"]
state = {"shutdown_calls": 0, "completed": 0, "child_pids": []}


class ControlServer(BoundedServer):
    def shutdown(self):
        state["shutdown_calls"] += 1
        state["shutdown_thread"] = threading.current_thread().name
        return super().shutdown()


class ControlHandler(Handler):
    def do_POST(self):
        self.rfile.read(int(self.headers["Content-Length"]))
        self._finish_input()
        # An inert, credential-free owned child exercises worker/child joining.
        # It does not parse content or emit a decoder/signature/receipt DTO.
        process = subprocess.Popen(
            [sys.executable, "-I", "-c", "import time; time.sleep(0.25)"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env={"PATH": "/usr/bin:/bin", "PYTHONDONTWRITEBYTECODE": "1"},
            cwd=str(directory),
        )
        state["child_pids"].append(process.pid)
        (directory / "child-started").write_text(str(process.pid))
        try:
            process.wait(timeout=namespace["DECODE_TIMEOUT"])
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
        state["completed"] += 1
        self.reply({"control_complete": True})


server = ControlServer(("127.0.0.1", 0), ControlHandler)
(directory / "port").write_text(str(server.server_address[1]))
namespace["serve_until_signalled"](server)
state["threads_after_close"] = [thread.name for thread in threading.enumerate()]
state["pid"] = os.getpid()
print(json.dumps(state, sort_keys=True))
