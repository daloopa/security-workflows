#!/usr/bin/env python3
"""Print a workflow step's `run` script, or one of its `env` values, selected by step id.

The tests execute the workflow's own scripts, so there is a single source of truth.
Usage: extract_step.py <workflow.yml> <step-id> [--env NAME]
"""
import sys

import yaml

if len(sys.argv) not in (3, 5):
    sys.exit(__doc__)
wf, step_id = sys.argv[1], sys.argv[2]
with open(wf) as fh:
    doc = yaml.safe_load(fh)
for job in doc["jobs"].values():
    for step in job.get("steps", []):
        if step.get("id") == step_id:
            if len(sys.argv) == 5:
                print(step["env"][sys.argv[4]], end="")
            else:
                print(step["run"], end="")
            sys.exit(0)
sys.exit(f"step id {step_id!r} not found in {wf}")
