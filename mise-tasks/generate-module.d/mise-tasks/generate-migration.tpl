#!/usr/bin/env python3
#MISE description="Generate and register a MySQL migration"

import json
from pathlib import Path
import re
import subprocess
import sys
import time


if len(sys.argv) < 2:
    sys.exit('Usage: mise run //modules/template:generate-migration "Description"')

module_root = Path(__file__).resolve().parent.parent
migration_dir = module_root / "internal/template/infra/mysql/migrations"
versions = [int(path.stem.removeprefix("version")) for path in migration_dir.glob("version*.go") if re.fullmatch(r"version[0-9]+", path.stem)]
version = max(int(time.time()), max(versions, default=0) + 1)
description = json.dumps(" ".join(sys.argv[1:]), ensure_ascii=False)
factory = migration_dir / "factory.go"
original_factory = factory.read_text()
pattern = r"(var migrations = \[\]mysqlMigration\{)(.*?)(\n\})"
match = re.search(pattern, original_factory, re.S)
if match is None:
    sys.exit("Cannot locate the migration registry in factory.go")

migration = migration_dir / f"version{version}.go"
source = f'''package migrations

import (
    "context"
    "errors"

    "github.com/distributed-programming-2026/go-sdk/pkg/migrator"
    "github.com/distributed-programming-2026/go-sdk/pkg/mysql"
)

func Version{version}(client mysql.ClientContext) migrator.Migration {{
    return &version{version}{{
        client: client,
    }}
}}

type version{version} struct {{
    client mysql.ClientContext
}}

func (v *version{version}) Version() int64 {{
    return {version}
}}

func (v *version{version}) Description() string {{
    return {description}
}}

func (v *version{version}) Up(ctx context.Context) error {{
    // TODO: implement the schema change using v.client.ExecContext(ctx, ...).
    err := ctx.Err()
    if err != nil {{
        return err
    }}
    return errors.New("migration {version} is not implemented")
}}
'''
new_factory = original_factory[:match.start(3)] + f"\n\tVersion{version}," + original_factory[match.start(3):]
try:
    migration.write_text(source)
    factory.write_text(new_factory)
    subprocess.run(["mise", "exec", "--", "gofmt", "-w", str(migration), str(factory)], cwd=module_root, check=True)
except BaseException:
    migration.unlink(missing_ok=True)
    factory.write_text(original_factory)
    raise
print(f"Created {migration.relative_to(module_root)}. Implement Up before starting the service.")
