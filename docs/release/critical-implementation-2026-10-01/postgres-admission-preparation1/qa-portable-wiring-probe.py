import sys,unittest
from pathlib import Path
p=Path(__file__).parent
sys.path.insert(0,str(p/"candidate2/scripts/tests"))
import supabase_delivery_contract_test as t
# Only this existing consumer reads ROOT/Makefile.
t.ROOT=p/"ci-wiring"
suite=unittest.TestSuite([t.SupabaseDeliveryContractTest("test_make_tool_defaults_use_path_and_keep_explicit_overrides")])
# Setup needs the full candidate source before the method selects its Makefile.
original=t.SupabaseDeliveryContractTest.setUp
def setup(self):
 t.ROOT=p/"candidate2"
 original(self)
 t.ROOT=p/"ci-wiring"
t.SupabaseDeliveryContractTest.setUp=setup
r=unittest.TextTestRunner(verbosity=2).run(suite)
raise SystemExit(0 if r.wasSuccessful() else 1)
