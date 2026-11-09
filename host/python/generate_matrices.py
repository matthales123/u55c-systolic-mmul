#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import json
import random
from pathlib import Path
from typing import Any, Dict, List


INLINE_DIM_MAX_DEFAULT = 1024


def make_row(dim: int, min_value: int, max_value: int, rng: random.Random) -> List[int]:
    return [rng.randint(min_value, max_value) for _ in range(dim)]


def make_matrix(dim: int, min_value: int, max_value: int, rng: random.Random) -> List[List[int]]:
    return [make_row(dim, min_value, max_value, rng) for _ in range(dim)]


def write_csv_stream(path: Path, dim: int, min_value: int, max_value: int, rng: random.Random) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f)
        for _ in range(dim):
            writer.writerow(make_row(dim, min_value, max_value, rng))


def write_json_stream(path: Path, dim: int, min_value: int, max_value: int, rng: random.Random) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        f.write("[\n")
        for row_idx in range(dim):
            row_text = json.dumps(make_row(dim, min_value, max_value, rng))
            if row_idx > 0:
                f.write(",\n")
            f.write(row_text)
        f.write("\n]\n")


def write_matrix(path: Path, dim: int, min_value: int, max_value: int, rng: random.Random, fmt: str) -> None:
    if fmt == "json":
        write_json_stream(path, dim, min_value, max_value, rng)
    else:
        write_csv_stream(path, dim, min_value, max_value, rng)


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Generate square random matrices for systolic MMUL workflows.",
    )
    p.add_argument("--dim", type=int, required=True, help="Matrix dimension N (N x N).")
    p.add_argument("--min", dest="min_value", type=int, default=-1000, help="Minimum random value.")
    p.add_argument("--max", dest="max_value", type=int, default=1000, help="Maximum random value.")
    p.add_argument("--seed", type=int, default=None, help="Optional RNG seed.")
    p.add_argument("--out-a", type=Path, default=None, help="Optional output file for matrix A.")
    p.add_argument("--out-b", type=Path, default=None, help="Optional output file for matrix B.")
    p.add_argument(
        "--format",
        choices=("json", "csv"),
        default="json",
        help="Output format used when writing --out-a/--out-b.",
    )
    p.add_argument(
        "--stdout-json",
        action="store_true",
        help="Emit JSON payload {'matrix_a': ..., 'matrix_b': ...} to stdout.",
    )
    p.add_argument(
        "--inline-max",
        type=int,
        default=INLINE_DIM_MAX_DEFAULT,
        help="Max dim allowed for stdout JSON matrix payload.",
    )
    return p.parse_args()


def main() -> int:
    args = parse_args()
    if args.dim < 1:
        raise SystemExit("--dim must be >= 1")
    if args.max_value < args.min_value:
        raise SystemExit("--max must be >= --min")
    if args.inline_max < 1:
        raise SystemExit("--inline-max must be >= 1")

    rng = random.Random(args.seed)
    writing_files = bool(args.out_a or args.out_b)

    if writing_files:
        if args.out_a:
            write_matrix(args.out_a, args.dim, args.min_value, args.max_value, rng, args.format)
        if args.out_b:
            write_matrix(args.out_b, args.dim, args.min_value, args.max_value, rng, args.format)

    if args.stdout_json or not writing_files:
        if args.dim > args.inline_max:
            raise SystemExit(
                f"dim {args.dim} exceeds inline JSON limit {args.inline_max}; "
                "use --out-a/--out-b for large matrix generation"
            )
        matrix_a = make_matrix(args.dim, args.min_value, args.max_value, rng)
        matrix_b = make_matrix(args.dim, args.min_value, args.max_value, rng)
        print(json.dumps({"matrix_a": matrix_a, "matrix_b": matrix_b}))
        return 0

    out: Dict[str, Any] = {
        "ok": True,
        "dim": args.dim,
        "format": args.format,
        "out_a": str(args.out_a) if args.out_a else "",
        "out_b": str(args.out_b) if args.out_b else "",
    }
    print(json.dumps(out))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
