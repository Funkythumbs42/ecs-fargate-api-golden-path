#!/usr/bin/env python3
"""Fail a code-pipeline terraform plan that touches anything other than
the task definition / ECS service. Those other resources belong on infra.
"""
import json
import sys

ALLOWED = {"aws_ecs_task_definition", "aws_ecs_service"}


def main() -> int:
    plan = json.load(sys.stdin)
    bad = []
    for change in plan.get("resource_changes") or []:
        actions = [
            a
            for a in (change.get("change") or {}).get("actions") or []
            if a != "no-op"
        ]
        if not actions:
            continue
        rtype = change.get("type") or ""
        addr = change.get("address") or rtype
        if rtype not in ALLOWED:
            bad.append(f"{addr} ({','.join(actions)})")
    if bad:
        print("code/rollback pipeline cannot change infra resources:", file=sys.stderr)
        for line in bad:
            print(f"  {line}", file=sys.stderr)
        print("Use the infra pipeline (current Terraform + digest from state).", file=sys.stderr)
        return 1
    print("code plan is image/service only")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
