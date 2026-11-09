#!/usr/bin/env python3
from __future__ import annotations

import os
import json
import random
import re
import shlex
import subprocess
import time
import math
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

APP_NAME = "Systolic-Array Matrix Multiplication Tool"
ROOT_DIR = Path(__file__).resolve().parents[1]
STATIC_DIR = Path(__file__).resolve().parent / "static"
PROJECT_ENV = ROOT_DIR / "config" / "project.env"
BENCH_BIN = ROOT_DIR / "build" / "host" / "u55c_bench"
BUILD_HOST_SCRIPT = ROOT_DIR / "scripts" / "build_host.sh"
MATRIX_GEN_SCRIPT = ROOT_DIR / "host" / "python" / "generate_matrices.py"
GENERATED_MATRICES_DIR = ROOT_DIR / "results" / "generated_matrices"
README_ROOT = ROOT_DIR / "README"
README_ASSETS = README_ROOT / "assets"
TOP_README = ROOT_DIR / "README.md"
INLINE_MATRIX_DIM_MAX = 1024

XRT_SMI = os.environ.get("MMUL_WEB_XRT_SMI", "/opt/xilinx/xrt/bin/xrt-smi")


class MatrixComputeRequest(BaseModel):
    matrix_a: List[List[float]]
    matrix_b: List[List[float]]
    trace_row: Optional[int] = Field(default=None, ge=0)
    trace_col: Optional[int] = Field(default=None, ge=0)


class RandomMatrixRequest(BaseModel):
    dim: int = Field(ge=1, le=1024)
    min_value: int = -1000
    max_value: int = 1000
    seed: Optional[int] = None


class ScriptRandomMatrixRequest(BaseModel):
    dim: int = Field(ge=1, le=10000)
    min_value: int = -1000
    max_value: int = 1000
    seed: Optional[int] = None
    file_format: str = Field(default="csv")


class BenchmarkRequest(BaseModel):
    dim: int = Field(ge=1, le=10000)
    mode: str = Field(default="hw")
    kernel: str = Field(default="mmul")
    iterations: int = Field(default=1, ge=1, le=50)
    device: str = Field(default="0")
    control: str = Field(default="legacy")
    scheduler: str = Field(default="kernel-tiled")
    tile_m: int = Field(default=16, ge=1, le=1024)
    tile_n: int = Field(default=16, ge=1, le=1024)
    tile_k: int = Field(default=16, ge=1, le=1024)
    xclbin_path: str = ""
    rebuild_host: bool = False
    matrix_a_path: str = ""
    matrix_b_path: str = ""
    matrix_a: Optional[List[List[float]]] = None
    matrix_b: Optional[List[List[float]]] = None


class ProgramRequest(BaseModel):
    xclbin_path: str = ""
    device: str = "0"


class DocRequest(BaseModel):
    key: str


app = FastAPI(title="Systolic-Array Matrix Multiplication Tool")
app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")
if README_ASSETS.exists():
    app.mount("/README/assets", StaticFiles(directory=str(README_ASSETS)), name="readme_assets")


def read_project_env() -> Dict[str, str]:
    values: Dict[str, str] = {}
    if not PROJECT_ENV.exists():
        return values
    for raw in PROJECT_ENV.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip('"').strip("'")
    return values


def startup_gate_state() -> Dict[str, Any]:
    status_raw = os.environ.get(
        "MMUL_WEB_STARTUP_GATE_STATUS",
        os.environ.get("WEBAPP_STARTUP_GATE_STATUS", "ok"),
    ).strip().lower()
    message = os.environ.get(
        "MMUL_WEB_STARTUP_GATE_MESSAGE",
        os.environ.get("WEBAPP_STARTUP_GATE_MESSAGE", ""),
    ).strip()
    rc_raw = os.environ.get(
        "MMUL_WEB_STARTUP_GATE_RC",
        os.environ.get("WEBAPP_STARTUP_GATE_RC", "0"),
    ).strip()

    status = status_raw if status_raw in {"ok", "warn", "skipped"} else "unknown"
    try:
        rc: Optional[int] = int(rc_raw)
    except ValueError:
        rc = None

    return {
        "status": status,
        "message": message,
        "rc": rc,
    }


def resolve_project_path(path_value: str) -> Path:
    expanded = Path(os.path.expandvars(os.path.expanduser(path_value)))
    if expanded.is_absolute():
        return expanded
    return (ROOT_DIR / expanded).resolve()


def matrix_shape(m: List[List[float]]) -> Tuple[int, int]:
    rows = len(m)
    cols = len(m[0]) if rows else 0
    return rows, cols


def validate_rectangular(m: List[List[float]], name: str) -> None:
    if not m or not m[0]:
        raise HTTPException(status_code=400, detail=f"{name} cannot be empty")
    cols = len(m[0])
    if cols == 0:
        raise HTTPException(status_code=400, detail=f"{name} cannot have zero columns")
    for idx, row in enumerate(m):
        if len(row) != cols:
            raise HTTPException(status_code=400, detail=f"{name} row {idx} has inconsistent column count")


def validate_integer_matrix(m: List[List[float]], name: str) -> None:
    for r, row in enumerate(m):
        for c, cell in enumerate(row):
            if not isinstance(cell, (int, float)) or not math.isfinite(float(cell)):
                raise HTTPException(
                    status_code=400,
                    detail=f"{name}[{r}][{c}] is not a finite number",
                )
            if not float(cell).is_integer():
                raise HTTPException(
                    status_code=400,
                    detail=(
                        f"{name}[{r}][{c}]={cell} is non-integer; "
                        "FPGA benchmark path currently supports integer-valued matrices"
                    ),
                )


def write_matrix_csv(path: Path, matrix: List[List[float]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        for row in matrix:
            f.write(",".join(str(int(v)) for v in row))
            f.write("\n")


def multiply_matrices(a: List[List[float]], b: List[List[float]]) -> List[List[float]]:
    a_rows, a_cols = matrix_shape(a)
    b_rows, b_cols = matrix_shape(b)
    if a_cols != b_rows:
        raise HTTPException(
            status_code=400,
            detail=f"Shape mismatch: A is {a_rows}x{a_cols}, B is {b_rows}x{b_cols}. Need A.cols == B.rows",
        )

    out = [[0.0 for _ in range(b_cols)] for _ in range(a_rows)]
    for i in range(a_rows):
        for k in range(a_cols):
            aik = a[i][k]
            for j in range(b_cols):
                out[i][j] += aik * b[k][j]
    return out


def trace_cell(a: List[List[float]], b: List[List[float]], row: int, col: int) -> Dict[str, Any]:
    a_rows, a_cols = matrix_shape(a)
    b_rows, b_cols = matrix_shape(b)
    if row >= a_rows or col >= b_cols:
        raise HTTPException(status_code=400, detail="trace cell is out of range")
    if a_cols != b_rows:
        raise HTTPException(status_code=400, detail="cannot trace cell for mismatched shapes")

    terms = []
    total = 0.0
    for k in range(a_cols):
        aval = a[row][k]
        bval = b[k][col]
        prod = aval * bval
        total += prod
        terms.append({"k": k, "a": aval, "b": bval, "product": prod, "partial_sum": total})
    return {"row": row, "col": col, "terms": terms, "sum": total}


def ensure_host_binary(rebuild: bool) -> None:
    if rebuild or not BENCH_BIN.exists():
        if not BUILD_HOST_SCRIPT.exists():
            raise HTTPException(status_code=500, detail=f"missing build script: {BUILD_HOST_SCRIPT}")
        proc = subprocess.run(
            [str(BUILD_HOST_SCRIPT)],
            cwd=str(ROOT_DIR),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=300,
            check=False,
        )
        if proc.returncode != 0:
            raise HTTPException(status_code=500, detail=f"host build failed\n{proc.stdout[-4000:]}")


def parse_bench_summary(text: str) -> Dict[str, Any]:
    mode_lines = [line.strip() for line in text.splitlines() if line.strip().startswith("mode=")]
    if not mode_lines:
        return {"summary_line": "", "metrics": {}}

    summary = mode_lines[-1]
    metrics: Dict[str, Any] = {}
    for token in summary.split():
        if "=" not in token:
            continue
        key, value = token.split("=", 1)
        raw = value.strip().strip(",")
        if re.fullmatch(r"[-+]?\d+", raw):
            metrics[key] = int(raw)
        elif re.fullmatch(r"[-+]?\d*\.\d+", raw):
            metrics[key] = float(raw)
        else:
            metrics[key] = raw
    return {"summary_line": summary, "metrics": metrics}


def run_command(cmd: List[str], timeout_s: int = 180, cwd: Optional[Path] = None) -> Dict[str, Any]:
    start = time.perf_counter()
    proc = subprocess.run(
        cmd,
        cwd=str(cwd) if cwd else None,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=timeout_s,
        check=False,
    )
    elapsed_ms = (time.perf_counter() - start) * 1000.0
    return {
        "ok": proc.returncode == 0,
        "rc": proc.returncode,
        "elapsed_ms": elapsed_ms,
        "cmd": " ".join(shlex.quote(x) for x in cmd),
        "output": proc.stdout,
    }


def docs_catalog() -> Dict[str, Path]:
    docs: Dict[str, Path] = {}
    hidden_docs = {"RUNBOOK.md", "WEBAPP.md", "TESTS.md", "SETUP.md", "INTERNAL_MILESTONES.md"}
    if TOP_README.exists():
        docs["README.md"] = TOP_README
    if README_ROOT.exists():
        for p in sorted(README_ROOT.glob("*.md")):
            if p.name in hidden_docs:
                continue
            docs[f"README/{p.name}"] = p
    return docs


def block_diagram_data() -> Dict[str, Any]:
    views: Dict[str, Dict[str, Any]] = {
        "top": {
            "id": "top",
            "title": "Top-Level Accelerator Picture",
            "description": "System-level path from host dispatch to HBM movement and systolic compute.",
            "notes": [
                "Host software controls launch, data buffers, and benchmark orchestration.",
                "HBM provides high-bandwidth backing storage for matrix tiles.",
                "Systolic core executes compute while scheduler/load-store drives tile flow.",
            ],
            "nodes": [
                {
                    "id": "host",
                    "label": "Host Runtime",
                    "subtitle": "u55c_bench / Python orchestration",
                    "x": 30,
                    "y": 70,
                    "w": 210,
                    "h": 100,
                    "group": "software",
                    "details": "C++ host app allocates buffers, transfers data, and launches kernels. Python tooling drives sweeps and plotting.",
                    "drill_to": "host_runtime",
                    "notes": [
                        "Runtime sets control mode and scheduler strategy.",
                        "Collects latency + throughput statistics for each run.",
                    ],
                },
                {
                    "id": "xrt",
                    "label": "XRT + PCIe Shell",
                    "subtitle": "Command + platform mediation",
                    "x": 280,
                    "y": 70,
                    "w": 220,
                    "h": 100,
                    "group": "platform",
                    "details": "XRT programs xclbin, binds compute units, and mediates host-to-card command flow.",
                },
                {
                    "id": "hbm",
                    "label": "HBM Fabric",
                    "subtitle": "A/B/C tile backing storage",
                    "x": 540,
                    "y": 50,
                    "w": 230,
                    "h": 140,
                    "group": "memory",
                    "details": "Explicit bank mapping keeps matrix streams separated: A->HBM0, B->HBM1, C->HBM2 by default.",
                    "drill_to": "hbm_memory",
                },
                {
                    "id": "scheduler",
                    "label": "Tile Scheduler",
                    "subtitle": "M/N/K traversal control",
                    "x": 40,
                    "y": 250,
                    "w": 220,
                    "h": 110,
                    "group": "control",
                    "details": "Traverses tiles, handles zero-padding edges, and sequences load/compute/store phases.",
                    "drill_to": "scheduler_control",
                },
                {
                    "id": "loader",
                    "label": "Load/Store Path",
                    "subtitle": "Tile marshaling",
                    "x": 300,
                    "y": 250,
                    "w": 210,
                    "h": 110,
                    "group": "datapath",
                    "details": "Moves tiles from HBM into compute staging and writes completed C tiles back.",
                },
                {
                    "id": "sysbase",
                    "label": "SysBase Systolic Core",
                    "subtitle": "PE wavefront compute",
                    "x": 560,
                    "y": 240,
                    "w": 250,
                    "h": 130,
                    "group": "compute",
                    "details": "Primary compute engine. Full tiles map to systolic execution; partial tiles use deterministic edge-safe handling.",
                    "drill_to": "sysbase_overview",
                },
                {
                    "id": "results",
                    "label": "Results + Profiling",
                    "subtitle": "CSV, logs, plots",
                    "x": 300,
                    "y": 430,
                    "w": 230,
                    "h": 110,
                    "group": "observability",
                    "details": "Collects execution timing and bandwidth metrics and saves benchmark history.",
                },
            ],
            "edges": [
                {"from": "host", "to": "xrt", "label": "launch/program"},
                {"from": "xrt", "to": "scheduler", "label": "kernel start"},
                {"from": "scheduler", "to": "loader", "label": "tile coords"},
                {"from": "loader", "to": "sysbase", "label": "A/B tile streams"},
                {"from": "sysbase", "to": "loader", "label": "C accum tile"},
                {"from": "loader", "to": "hbm", "label": "HBM read/write"},
                {"from": "scheduler", "to": "results", "label": "counters"},
                {"from": "results", "to": "host", "label": "telemetry"},
            ],
        },
        "sysbase_overview": {
            "id": "sysbase_overview",
            "title": "SysBase Core Breakdown",
            "description": "Internal composition of the systolic compute subsystem.",
            "notes": [
                "Input staging controls wavefront injection timing.",
                "PE mesh propagates A across rows and B across columns.",
                "Accumulator/output path consolidates partial sums to output tiles.",
            ],
            "nodes": [
                {
                    "id": "tile_in",
                    "label": "Tile Input Buffers",
                    "subtitle": "A/B tile staging",
                    "x": 50,
                    "y": 200,
                    "w": 220,
                    "h": 120,
                    "group": "internals",
                    "details": "Local staging buffers align tile payloads before wavefront injection.",
                },
                {
                    "id": "wave_ctrl",
                    "label": "Wavefront Controller",
                    "subtitle": "Row/column launch timing",
                    "x": 320,
                    "y": 70,
                    "w": 250,
                    "h": 110,
                    "group": "control",
                    "details": "Controls launch order and temporal skew needed for systolic propagation.",
                },
                {
                    "id": "pe_mesh",
                    "label": "PE Mesh",
                    "subtitle": "N x N multiply-accumulate cells",
                    "x": 320,
                    "y": 220,
                    "w": 250,
                    "h": 180,
                    "group": "compute",
                    "details": "Core compute matrix where each PE consumes streamed A/B values and accumulates products.",
                    "drill_to": "pe_mesh_grid",
                },
                {
                    "id": "accum_out",
                    "label": "Accumulator + Drain",
                    "subtitle": "C tile reconstruction",
                    "x": 640,
                    "y": 210,
                    "w": 270,
                    "h": 140,
                    "group": "datapath",
                    "details": "Collects PE outputs, resolves k-tile accumulation, and forwards finished C tiles.",
                },
            ],
            "edges": [
                {"from": "tile_in", "to": "wave_ctrl", "label": "ready/valid"},
                {"from": "wave_ctrl", "to": "pe_mesh", "label": "launch strobes"},
                {"from": "tile_in", "to": "pe_mesh", "label": "A/B data lanes"},
                {"from": "pe_mesh", "to": "accum_out", "label": "partial sums"},
            ],
        },
        "pe_mesh_grid": {
            "id": "pe_mesh_grid",
            "title": "PE Mesh Dataflow Explorer",
            "description": "Dynamic mesh view tied to Matrix Lab N (rendered as min(N, 5) for readability).",
            "notes": [
                "HBM feeds tile buffers and controller metadata.",
                "Controller schedules wavefront injection into the PE mesh.",
                "PE-to-PE movement and accumulator/drain flow are shown with orthogonal routing.",
                "Click an individual PE and drill into PE Detail for local datapath context.",
            ],
            "dynamic_mesh": True,
            "dynamic_mesh_max_n": 5,
            "nodes": [],
            "edges": [],
        },
        "pe_cell": {
            "id": "pe_cell",
            "title": "Processing Element (PE) Detail",
            "description": "Representative systolic PE datapath and forwarding behavior.",
            "notes": [
                "PE is multiply-accumulate centric.",
                "A is forwarded horizontally, B vertically.",
                "Local accumulator stores partial sum across k steps.",
            ],
            "nodes": [
                {
                    "id": "a_in",
                    "label": "A_in Register",
                    "x": 80,
                    "y": 210,
                    "w": 170,
                    "h": 90,
                    "group": "datapath",
                    "details": "Captures incoming A operand for local multiply and forward path.",
                },
                {
                    "id": "b_in",
                    "label": "B_in Register",
                    "x": 80,
                    "y": 350,
                    "w": 170,
                    "h": 90,
                    "group": "datapath",
                    "details": "Captures incoming B operand for local multiply and forward path.",
                },
                {
                    "id": "mul",
                    "label": "Multiplier",
                    "x": 320,
                    "y": 270,
                    "w": 180,
                    "h": 110,
                    "group": "compute",
                    "details": "Computes A * B each cycle for the current wavefront element.",
                },
                {
                    "id": "acc",
                    "label": "Accumulator Register",
                    "x": 570,
                    "y": 270,
                    "w": 210,
                    "h": 110,
                    "group": "compute",
                    "details": "Adds product into running partial sum and emits output when tile step completes.",
                },
                {
                    "id": "fwd",
                    "label": "Forward Paths",
                    "x": 830,
                    "y": 250,
                    "w": 130,
                    "h": 160,
                    "group": "datapath",
                    "details": "Passes A_right and B_down to neighbor PEs to sustain systolic movement.",
                },
            ],
            "edges": [
                {"from": "a_in", "to": "mul", "label": "A"},
                {"from": "b_in", "to": "mul", "label": "B"},
                {"from": "mul", "to": "acc", "label": "product"},
                {"from": "acc", "to": "fwd", "label": "sum + fwd ctl"},
            ],
        },
        "scheduler_control": {
            "id": "scheduler_control",
            "title": "Scheduler + Control FSM",
            "description": "Macro-level sequencing that drives tiled execution for arbitrary N x N matrices.",
            "notes": [
                "Zero-padding is handled when tile indices exceed active matrix bounds.",
                "Tile loop ordering controls k-accumulation behavior.",
                "Descriptor/legacy modes can share this control envelope.",
            ],
            "nodes": [
                {
                    "id": "cfg",
                    "label": "Config Registers",
                    "subtitle": "dim / tile sizes / mode",
                    "x": 70,
                    "y": 120,
                    "w": 220,
                    "h": 100,
                    "group": "control",
                    "details": "Captures runtime parameters including matrix dimension and tile geometry.",
                },
                {
                    "id": "loop",
                    "label": "Tile Loop Engine",
                    "subtitle": "(m,n,k) traversal",
                    "x": 350,
                    "y": 120,
                    "w": 240,
                    "h": 120,
                    "group": "control",
                    "details": "Traverses tile coordinates and emits next tile command sequence.",
                },
                {
                    "id": "pad",
                    "label": "Boundary + Zero Pad Logic",
                    "subtitle": "edge protection",
                    "x": 650,
                    "y": 120,
                    "w": 280,
                    "h": 120,
                    "group": "datapath",
                    "details": "Masks out-of-range indices and injects zeros for partial edge tiles.",
                },
                {
                    "id": "dispatch",
                    "label": "Load/Compute/Store Dispatcher",
                    "subtitle": "phase scheduling",
                    "x": 310,
                    "y": 320,
                    "w": 360,
                    "h": 130,
                    "group": "control",
                    "details": "Arbitrates phase transitions and completion/ready signaling.",
                },
            ],
            "edges": [
                {"from": "cfg", "to": "loop", "label": "parameters"},
                {"from": "loop", "to": "pad", "label": "raw tile indices"},
                {"from": "pad", "to": "dispatch", "label": "validated tile cmds"},
                {"from": "loop", "to": "dispatch", "label": "state updates"},
            ],
        },
        "hbm_memory": {
            "id": "hbm_memory",
            "title": "HBM Memory Path",
            "description": "How matrix payloads are distributed and transferred across HBM-facing paths.",
            "nodes": [
                {
                    "id": "bank_a",
                    "label": "HBM[0] - Matrix A",
                    "x": 80,
                    "y": 120,
                    "w": 250,
                    "h": 100,
                    "group": "memory",
                    "details": "Read source for A tiles.",
                },
                {
                    "id": "bank_b",
                    "label": "HBM[1] - Matrix B",
                    "x": 360,
                    "y": 120,
                    "w": 250,
                    "h": 100,
                    "group": "memory",
                    "details": "Read source for B tiles.",
                },
                {
                    "id": "bank_c",
                    "label": "HBM[2] - Matrix C",
                    "x": 640,
                    "y": 120,
                    "w": 250,
                    "h": 100,
                    "group": "memory",
                    "details": "Write destination for C tiles.",
                },
                {
                    "id": "axi_read",
                    "label": "AXI Read Movers",
                    "x": 220,
                    "y": 310,
                    "w": 280,
                    "h": 120,
                    "group": "datapath",
                    "details": "Burst reads for A/B payloads into local staging.",
                },
                {
                    "id": "axi_write",
                    "label": "AXI Write Movers",
                    "x": 560,
                    "y": 310,
                    "w": 280,
                    "h": 120,
                    "group": "datapath",
                    "details": "Burst writes completed C tiles back to HBM.",
                },
            ],
            "edges": [
                {"from": "bank_a", "to": "axi_read", "label": "A bursts"},
                {"from": "bank_b", "to": "axi_read", "label": "B bursts"},
                {"from": "axi_write", "to": "bank_c", "label": "C bursts"},
            ],
        },
        "host_runtime": {
            "id": "host_runtime",
            "title": "Host Runtime Stack",
            "description": "Software layers used to configure, launch, and validate accelerator runs.",
            "nodes": [
                {
                    "id": "py_tools",
                    "label": "Python Tools",
                    "subtitle": "run_benchmark.py / plotting",
                    "x": 80,
                    "y": 110,
                    "w": 260,
                    "h": 120,
                    "group": "software",
                    "details": "Automation, sweeps, and plotting entry points.",
                },
                {
                    "id": "cpp_runtime",
                    "label": "C++ Runtime",
                    "subtitle": "u55c_bench",
                    "x": 380,
                    "y": 110,
                    "w": 260,
                    "h": 120,
                    "group": "software",
                    "details": "Core runner for xclbin loading, buffer management, and timing capture.",
                },
                {
                    "id": "xrt_api",
                    "label": "XRT API Layer",
                    "subtitle": "device/kernel/buffer APIs",
                    "x": 680,
                    "y": 110,
                    "w": 260,
                    "h": 120,
                    "group": "platform",
                    "details": "Connects host code to FPGA shell and kernels.",
                },
                {
                    "id": "csv_log",
                    "label": "CSV + Metrics",
                    "subtitle": "results/benchmark_latest.csv",
                    "x": 350,
                    "y": 320,
                    "w": 340,
                    "h": 140,
                    "group": "observability",
                    "details": "Stores per-run timing + throughput + tile counters for post-analysis.",
                },
            ],
            "edges": [
                {"from": "py_tools", "to": "cpp_runtime", "label": "CLI orchestration"},
                {"from": "cpp_runtime", "to": "xrt_api", "label": "runtime API calls"},
                {"from": "cpp_runtime", "to": "csv_log", "label": "benchmark rows"},
            ],
        },
    }

    return {
        "root_view": "top",
        "views": views,
    }


@app.get("/")
def root() -> FileResponse:
    return FileResponse(STATIC_DIR / "index.html")


@app.get("/api/health")
def api_health() -> Dict[str, Any]:
    env = read_project_env()
    gate = startup_gate_state()
    try:
        web_port = int(os.environ.get("MMUL_WEB_PORT", "9890"))
    except ValueError:
        web_port = 9890
    return {
        "ok": True,
        "app": APP_NAME,
        "web_port": web_port,
        "workspace_dim_max": 1024,
        "benchmark_dim_max": 10000,
        "script_dim_max": 10000,
        "project_root": str(ROOT_DIR),
        "default_kernel": env.get("U55C_KERNEL_NAME", "mmul"),
        "default_xclbin": str(resolve_project_path(env.get("U55C_XCLBIN", ""))) if env.get("U55C_XCLBIN") else "",
        "startup_gate": gate,
    }


@app.post("/api/matmul/random")
def api_random_matrices(req: RandomMatrixRequest) -> Dict[str, Any]:
    if req.max_value < req.min_value:
        raise HTTPException(status_code=400, detail="max_value must be >= min_value")
    rng = random.Random(req.seed)
    a = [[rng.randint(req.min_value, req.max_value) for _ in range(req.dim)] for _ in range(req.dim)]
    b = [[rng.randint(req.min_value, req.max_value) for _ in range(req.dim)] for _ in range(req.dim)]
    return {"matrix_a": a, "matrix_b": b}


@app.post("/api/matmul/random-script")
def api_random_matrices_script(req: ScriptRandomMatrixRequest) -> Dict[str, Any]:
    if req.max_value < req.min_value:
        raise HTTPException(status_code=400, detail="max_value must be >= min_value")
    file_format = req.file_format.strip().lower()
    if file_format not in ("csv", "json"):
        raise HTTPException(status_code=400, detail="file_format must be one of: csv, json")

    if not MATRIX_GEN_SCRIPT.exists():
        raise HTTPException(status_code=500, detail=f"matrix generator script not found: {MATRIX_GEN_SCRIPT}")

    if req.dim <= INLINE_MATRIX_DIM_MAX:
        cmd = [
            "python3",
            str(MATRIX_GEN_SCRIPT),
            "--dim",
            str(req.dim),
            "--min",
            str(req.min_value),
            "--max",
            str(req.max_value),
            "--stdout-json",
        ]
        if req.seed is not None:
            cmd.extend(["--seed", str(req.seed)])

        result = run_command(cmd, timeout_s=180, cwd=ROOT_DIR)
        if not result["ok"]:
            tail = "\n".join(result["output"].splitlines()[-20:])
            raise HTTPException(status_code=500, detail=f"matrix script failed (rc={result['rc']})\n{tail}")

        try:
            payload = json.loads(result["output"])
        except json.JSONDecodeError as err:
            tail = "\n".join(result["output"].splitlines()[-20:])
            raise HTTPException(status_code=500, detail=f"matrix script returned invalid JSON: {err}\n{tail}") from err

        a = payload.get("matrix_a")
        b = payload.get("matrix_b")
        if not isinstance(a, list) or not isinstance(b, list):
            raise HTTPException(status_code=500, detail="matrix script JSON missing matrix_a/matrix_b")
        return {
            "mode": "inline",
            "dim": req.dim,
            "matrix_a": a,
            "matrix_b": b,
        }

    GENERATED_MATRICES_DIR.mkdir(parents=True, exist_ok=True)
    stamp = time.strftime("%Y%m%d_%H%M%S")
    seed_label = f"s{req.seed}" if req.seed is not None else "srand"
    base_name = f"rand_n{req.dim}_{seed_label}_{stamp}"
    out_a = GENERATED_MATRICES_DIR / f"{base_name}_A.{file_format}"
    out_b = GENERATED_MATRICES_DIR / f"{base_name}_B.{file_format}"

    cmd = [
        "python3",
        str(MATRIX_GEN_SCRIPT),
        "--dim",
        str(req.dim),
        "--min",
        str(req.min_value),
        "--max",
        str(req.max_value),
        "--format",
        file_format,
        "--out-a",
        str(out_a),
        "--out-b",
        str(out_b),
    ]
    if req.seed is not None:
        cmd.extend(["--seed", str(req.seed)])

    result = run_command(cmd, timeout_s=7200, cwd=ROOT_DIR)
    if not result["ok"]:
        tail = "\n".join(result["output"].splitlines()[-20:])
        raise HTTPException(status_code=500, detail=f"matrix file generation failed (rc={result['rc']})\n{tail}")

    if not out_a.exists() or not out_b.exists():
        raise HTTPException(status_code=500, detail="matrix generation completed but output files are missing")

    entries = req.dim * req.dim
    return {
        "mode": "files",
        "dim": req.dim,
        "file_format": file_format,
        "matrix_a_path": str(out_a),
        "matrix_b_path": str(out_b),
        "entries_per_matrix": entries,
        "total_values": entries * 2,
        "elapsed_ms": result["elapsed_ms"],
    }


@app.post("/api/matmul/compute")
def api_matmul_compute(req: MatrixComputeRequest) -> Dict[str, Any]:
    validate_rectangular(req.matrix_a, "matrix_a")
    validate_rectangular(req.matrix_b, "matrix_b")

    start = time.perf_counter()
    result = multiply_matrices(req.matrix_a, req.matrix_b)
    elapsed_ms = (time.perf_counter() - start) * 1000.0

    a_rows, a_cols = matrix_shape(req.matrix_a)
    b_rows, b_cols = matrix_shape(req.matrix_b)
    flops = 2 * a_rows * b_cols * a_cols

    trace = None
    if req.trace_row is not None and req.trace_col is not None:
        trace = trace_cell(req.matrix_a, req.matrix_b, req.trace_row, req.trace_col)

    return {
        "shape_a": [a_rows, a_cols],
        "shape_b": [b_rows, b_cols],
        "shape_out": [a_rows, b_cols],
        "elapsed_ms": elapsed_ms,
        "flops": flops,
        "gflops": (flops / 1e9) / (elapsed_ms / 1e3) if elapsed_ms > 0 else 0.0,
        "result": result,
        "trace": trace,
    }


@app.post("/api/benchmark")
def api_benchmark(req: BenchmarkRequest) -> Dict[str, Any]:
    mode = req.mode.strip().lower()
    if mode not in ("dry-run", "hw"):
        raise HTTPException(status_code=400, detail="mode must be dry-run or hw")

    ensure_host_binary(req.rebuild_host)
    env_cfg = read_project_env()
    xclbin_candidate = req.xclbin_path.strip() or env_cfg.get("U55C_XCLBIN", "")
    matrix_source: Dict[str, Any] = {"mode": "runtime-generated"}
    benchmark_dim = req.dim

    matrix_a_candidate = req.matrix_a_path.strip()
    matrix_b_candidate = req.matrix_b_path.strip()
    inline_a = req.matrix_a
    inline_b = req.matrix_b
    has_inline = inline_a is not None or inline_b is not None
    if has_inline and (matrix_a_candidate or matrix_b_candidate):
        raise HTTPException(
            status_code=400,
            detail="provide either inline matrices (matrix_a/matrix_b) or matrix file paths, not both",
        )

    resolved_matrix_a_path = ""
    resolved_matrix_b_path = ""

    if matrix_a_candidate or matrix_b_candidate:
        if not matrix_a_candidate or not matrix_b_candidate:
            raise HTTPException(status_code=400, detail="both matrix_a_path and matrix_b_path must be provided together")
        matrix_a_resolved = resolve_project_path(matrix_a_candidate)
        matrix_b_resolved = resolve_project_path(matrix_b_candidate)
        if not matrix_a_resolved.exists():
            raise HTTPException(status_code=404, detail=f"matrix_a_path not found: {matrix_a_resolved}")
        if not matrix_b_resolved.exists():
            raise HTTPException(status_code=404, detail=f"matrix_b_path not found: {matrix_b_resolved}")
        resolved_matrix_a_path = str(matrix_a_resolved)
        resolved_matrix_b_path = str(matrix_b_resolved)
        matrix_source = {
            "mode": "generated-files",
            "matrix_a_path": resolved_matrix_a_path,
            "matrix_b_path": resolved_matrix_b_path,
        }
    elif has_inline:
        if inline_a is None or inline_b is None:
            raise HTTPException(status_code=400, detail="both matrix_a and matrix_b must be provided together")
        validate_rectangular(inline_a, "matrix_a")
        validate_rectangular(inline_b, "matrix_b")
        validate_integer_matrix(inline_a, "matrix_a")
        validate_integer_matrix(inline_b, "matrix_b")
        a_rows, a_cols = matrix_shape(inline_a)
        b_rows, b_cols = matrix_shape(inline_b)
        if a_cols != b_rows:
            raise HTTPException(
                status_code=400,
                detail=f"Shape mismatch: A is {a_rows}x{a_cols}, B is {b_rows}x{b_cols}. Need A.cols == B.rows",
            )

        required_dim = max(a_rows, a_cols, b_cols)
        benchmark_dim = max(req.dim, required_dim)

        GENERATED_MATRICES_DIR.mkdir(parents=True, exist_ok=True)
        stamp = int(time.time() * 1000)
        base_name = f"web_inline_{a_rows}x{a_cols}_{b_rows}x{b_cols}_{benchmark_dim}_{stamp}"
        out_a = GENERATED_MATRICES_DIR / f"{base_name}_A.csv"
        out_b = GENERATED_MATRICES_DIR / f"{base_name}_B.csv"
        write_matrix_csv(out_a, inline_a)
        write_matrix_csv(out_b, inline_b)
        resolved_matrix_a_path = str(out_a.resolve())
        resolved_matrix_b_path = str(out_b.resolve())
        matrix_source = {
            "mode": "inline-zero-pad",
            "shape_a": [a_rows, a_cols],
            "shape_b": [b_rows, b_cols],
            "required_dim": required_dim,
            "run_dim": benchmark_dim,
            "matrix_a_path": resolved_matrix_a_path,
            "matrix_b_path": resolved_matrix_b_path,
        }

    cmd = [
        str(BENCH_BIN),
        "--mode",
        mode,
        "--kernel",
        req.kernel,
        "--device",
        req.device,
        "--elements",
        str(benchmark_dim * benchmark_dim),
        "--iterations",
        str(req.iterations),
        "--control",
        req.control,
        "--scheduler",
        req.scheduler,
        "--tile-m",
        str(req.tile_m),
        "--tile-n",
        str(req.tile_n),
        "--tile-k",
        str(req.tile_k),
        "--seed",
        "1",
    ]
    if resolved_matrix_a_path and resolved_matrix_b_path:
        cmd.extend(
            [
                "--matrix-a-path",
                resolved_matrix_a_path,
                "--matrix-b-path",
                resolved_matrix_b_path,
            ]
        )

    resolved_xclbin = ""
    if mode == "hw":
        if not xclbin_candidate:
            raise HTTPException(status_code=400, detail="hardware mode requires xclbin path")
        resolved = resolve_project_path(xclbin_candidate)
        if not resolved.exists():
            raise HTTPException(status_code=404, detail=f"xclbin not found: {resolved}")
        resolved_xclbin = str(resolved)
        cmd.extend(["--xclbin", resolved_xclbin])

    result = run_command(cmd, timeout_s=240, cwd=ROOT_DIR)
    summary = parse_bench_summary(result["output"])

    return {
        "ok": result["ok"],
        "return_code": result["rc"],
        "elapsed_ms": result["elapsed_ms"],
        "command": result["cmd"],
        "xclbin": resolved_xclbin,
        "matrix_source": matrix_source,
        "summary": summary,
        "output_tail": "\n".join(result["output"].splitlines()[-20:]),
    }


@app.get("/api/fpga/status")
def api_fpga_status(device: str = "0") -> Dict[str, Any]:
    if not Path(XRT_SMI).exists():
        raise HTTPException(status_code=500, detail=f"xrt-smi not found at {XRT_SMI}")

    cmd = [XRT_SMI, "examine", "--device", device, "--report", "dynamic-regions"]
    result = run_command(cmd, timeout_s=60)
    text = result["output"]

    uuid_match = re.search(r"Xclbin UUID:\s*([A-Fa-f0-9\-]+)", text)
    clean_cus: List[str] = []
    for line in text.splitlines():
        s = line.strip()
        if not s.startswith("|"):
            continue
        if "Index" in s or "Name" in s or "---" in s:
            continue
        parts = [p.strip() for p in s.split("|")]
        # Expected data row:
        # |Index|Name|Base Address|Usage|Status|
        if len(parts) < 6:
            continue
        if not parts[1].isdigit():
            continue
        name = parts[2]
        if name:
            clean_cus.append(name)

    return {
        "ok": result["ok"],
        "return_code": result["rc"],
        "command": result["cmd"],
        "xclbin_uuid": uuid_match.group(1) if uuid_match else "",
        "compute_units": clean_cus,
        "output": text,
    }


@app.post("/api/fpga/program")
def api_fpga_program(req: ProgramRequest) -> Dict[str, Any]:
    env_cfg = read_project_env()
    path_value = req.xclbin_path.strip() or env_cfg.get("U55C_XCLBIN", "")
    if not path_value:
        raise HTTPException(status_code=400, detail="xclbin path not provided")

    xclbin = resolve_project_path(path_value)
    if not xclbin.exists():
        raise HTTPException(status_code=404, detail=f"xclbin not found: {xclbin}")
    if xclbin.suffix.lower() != ".xclbin":
        raise HTTPException(status_code=400, detail="program path must end in .xclbin")

    cmd = [XRT_SMI, "--batch", "program", "--device", req.device, "--user", str(xclbin)]
    result = run_command(cmd, timeout_s=180)

    return {
        "ok": result["ok"],
        "return_code": result["rc"],
        "elapsed_ms": result["elapsed_ms"],
        "command": result["cmd"],
        "output": result["output"],
    }


@app.get("/api/docs/files")
def api_docs_files() -> Dict[str, Any]:
    docs = docs_catalog()
    return {
        "items": [
            {
                "key": key,
                "path": str(path),
            }
            for key, path in docs.items()
        ]
    }


@app.post("/api/docs/read")
def api_docs_read(req: DocRequest) -> Dict[str, Any]:
    docs = docs_catalog()
    path = docs.get(req.key)
    if not path:
        raise HTTPException(status_code=404, detail="doc key not found")
    text = path.read_text(encoding="utf-8", errors="replace")
    return {
        "key": req.key,
        "path": str(path),
        "text": text,
    }


@app.get("/api/block-diagram")
def api_block_diagram() -> Dict[str, Any]:
    return block_diagram_data()


if __name__ == "__main__":
    import uvicorn

    try:
        web_port = int(os.environ.get("MMUL_WEB_PORT", "9890"))
    except ValueError:
        web_port = 9890

    uvicorn.run(app, host="0.0.0.0", port=web_port, reload=False)
