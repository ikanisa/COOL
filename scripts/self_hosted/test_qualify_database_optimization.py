"""Exercise only the installer's pre-import optimization guard.

No installer, database, network, filesystem mutation or subprocess is run.
"""
import ast
from pathlib import Path
import unittest


class InstallerOptimizationGuardTest(unittest.TestCase):
    def test_guard_precedes_imports_and_refuses_optimized_bytecode(self):
        source = Path(__file__).with_name('qualify_database_installation.py').read_text()
        body = ast.parse(source).body
        # The module docstring and future imports may precede executable code.
        while body and (isinstance(body[0], ast.Expr) and
                        isinstance(body[0].value, ast.Constant) and
                        isinstance(body[0].value.value, str) or
                        isinstance(body[0], ast.ImportFrom) and body[0].module == '__future__'):
            body = body[1:]
        self.assertTrue(body)
        self.assertIsInstance(body[0], ast.If)
        marker = ast.Assign(targets=[ast.Name(id='continued', ctx=ast.Store())],
                            value=ast.Constant(value=True))
        probe = ast.fix_missing_locations(ast.Module(body=[body[0], marker], type_ignores=[]))
        for optimization in (1, 2):
            namespace = {}
            with self.subTest(optimization=optimization):
                with self.assertRaisesRegex(SystemExit, 'non-optimized Python'):
                    exec(compile(probe, '<installer-guard>', 'exec', optimize=optimization), namespace)
                self.assertNotIn('continued', namespace)
        namespace = {}
        exec(compile(probe, '<installer-guard>', 'exec', optimize=0), namespace)
        self.assertTrue(namespace['continued'])


if __name__ == '__main__':
    unittest.main()
