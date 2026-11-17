#!/usr/bin/env python3
"""Storage-metadata-only entry point; object bodies are out of scope."""
import importlib.util
import pathlib

supervisor = pathlib.Path(__file__).resolve().with_name('managed-supervisor.py')
spec = importlib.util.spec_from_file_location('collect_managed_supervisor', supervisor)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.run('storage')
