#!/usr/bin/env python3
"""Auth-only entry point with a fixed component."""
import importlib.util
import pathlib

supervisor = pathlib.Path(__file__).resolve().with_name('managed-supervisor.py')
spec = importlib.util.spec_from_file_location('collect_managed_supervisor', supervisor)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.run('auth')
