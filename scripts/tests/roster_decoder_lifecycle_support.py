"""Load canonical lifecycle definitions without signer/key/prctl admission.

Only the host test adapter uses this module. It starts no server, decoder,
subprocess, nonce database or signer at import time.
"""
import ast
import hashlib
from pathlib import Path

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
SOURCE=ROOT/"tools/roster-decoder/server.py"
CONTROL_WORKER=HERE/"roster_decoder_lifecycle_worker.py"
BASELINE_SOURCE_SHA256="87d3d98d094ffdbd1e35d2a6fe2f6a9d6406d5e09dcbf2b205d56e78e3d112c4"
# Derived from the retained preimage, not from the candidate under test.
SECURITY_AST_BASELINE={'signature': 'd8d989d172eb5c68b9c7ed68763318836c65c840aea7651622680b476b43e96d', 'normalized_do_POST': '5b9deaf6325894eb4c7a6c758a16344fc2f9dd39736d5325642528ef62c5a8b3', 'SECRET =': 'e6b635eae0f07316d1b9e74fb4b892be0fbf50892cd804722d78ea6698ab7a26', 'if len(SECRET': '9a5cdb729f120a8ddfb41d512788861be9aa87db06d6b475a455b008224a5f42', 'if sys.platform': '12e29fde1b25275c26624bc90c91c0b53c3d8eebe1df022dc6757f4ef575f2d3', 'DB =': 'e9625f2ce93e7548855bca599dba29f82f4c4e4e3a39806c774e7fe0b5ee2f56', 'NONCE_LOCK =': '786322c40a14eff3c59b4d441d44e640bca0911683aae2a227d7cf8fedfc4eee', 'with sqlite3.connect': '71f1f46b5437e5825e46dabd9fc21ae806efd62f14849e55fc460bfe5b45e432'}


def ast_identity(node):
    # No generic parameters exist in this source. Normalize only the empty
    # field introduced by Python3.12 so the same control also runs on3.11.
    value=ast.dump(node,include_attributes=False).replace(", type_params=[]","")
    return hashlib.sha256(value.encode()).hexdigest()


def load_lifecycle():
    tree=ast.parse(SOURCE.read_text(),filename=str(SOURCE))
    constants={"INPUT_TIMEOUT","DECODE_TIMEOUT","IO_TIMEOUT"}
    body=[]
    for node in tree.body:
        if isinstance(node,(ast.Import,ast.ImportFrom)):
            body.append(node)
        elif isinstance(node,ast.Assign) and any(
            isinstance(target,ast.Name) and target.id in constants for target in node.targets
        ):
            body.append(node)
        elif isinstance(node,(ast.ClassDef,ast.FunctionDef)) and node.name in {
            "BoundedServer","Handler","serve_until_signalled"
        }:
            body.append(node)
    namespace={"__name__":"lifecycle_control_fixture","LIMIT":8*1024*1024}
    exec(compile(ast.Module(body=body,type_ignores=[]),str(SOURCE),"exec"),namespace)
    return namespace
