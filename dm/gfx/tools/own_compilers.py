#!/usr/bin/env python3
"""Compatibility entry point for the strict local shader build.

All tools must match dmsh_chain.lock. A changed Metal compiler must invalidate
shader caches too; validate it before updating the lock and chain header.
"""
import os
import runpy
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.argv = [os.path.join(HERE, 'dmsh_build.py'), *sys.argv[1:]]
runpy.run_path(sys.argv[0], run_name='__main__')
