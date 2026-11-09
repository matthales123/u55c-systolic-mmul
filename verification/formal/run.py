#!/usr/bin/env python3
"""Run the scoped SysBase formal pilot and independent CSR defect replays.

PASS means all checks in this pilot passed their stated expectations. It is not
full arithmetic, parameter, CDC, timing, or board signoff. Generated SBY files,
source snapshots, logs, solver witnesses and VCDs are retained in --output-dir.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time


HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1]
WORKSPACE = Path(os.environ.get("FPGA_TOOLS_ROOT", PROJECT.parent / "fpga-verification-tools"))
_active_process: subprocess.Popen | None = None

CSR_ASSUMPTIONS = [
    "Reset is high at the first sampled clock; subsequent reset is unrestricted.",
    "CSR requests (including writes while busy), response readiness and memory inputs are unrestricted.",
    "The datapath shell outputs are unconstrained independently on every cycle (explicit over-approximation).",
    "No fairness or eventual-memory-response assumption is used; these are safety properties.",
]
SHELL_ASSUMPTIONS = [
    "Reset is low at the first sampled clock; subsequent reset and start are unrestricted.",
    "An input source holds valid and data while stalled, except across reset.",
    "Dimension is fixed at 1; ARRAY_SIZE=1, MAX_DIM=1, DATA_WIDTH=32, DIM_WIDTH=8.",
    "Output readiness and all 32 input data bits are unrestricted; no fairness assumption is used.",
]
AXI_ASSUMPTIONS = [
    "Reset is low at the first sampled clock; subsequent reset is unrestricted.",
    "All AXI/AXI-Lite request, response, payload and readiness inputs are unrestricted for the safety proof.",
    "The datapath shell outputs are unconstrained each cycle; no arithmetic or core-latency guarantee is assumed.",
    "Actual kernel defaults: MAX_DIM=8, ARRAY_SIZE=4, AXI address=64 bits, data=32 bits, ID/user=1 bit.",
    "No fairness or eventual-completion property is claimed.",
]


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path: Path, data: dict) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(data, indent=2) + "\n")
    temporary.replace(path)


def stop_process() -> None:
    global _active_process
    if _active_process is not None and _active_process.poll() is None:
        os.killpg(_active_process.pid, signal.SIGTERM)
        try:
            _active_process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(_active_process.pid, signal.SIGKILL)
            _active_process.wait()


def interrupted(signum, frame) -> None:
    stop_process()
    raise KeyboardInterrupt(f"interrupted by signal {signum}")


def command(args: list[str], cwd: Path, env: dict, log: Path, timeout: int) -> tuple[int, bool]:
    global _active_process
    with log.open("w") as stream:
        stream.write(json.dumps({"argv": args, "cwd": str(cwd)}) + "\n")
        stream.flush()
        _active_process = subprocess.Popen(args, cwd=cwd, env=env, stdout=stream,
                                           stderr=subprocess.STDOUT, start_new_session=True)
        try:
            return _active_process.wait(timeout=timeout), False
        except subprocess.TimeoutExpired:
            stop_process()
            return _active_process.returncode, True
        finally:
            _active_process = None


def vcd_states(path: Path, top: str) -> list[dict]:
    """Read sampled top-level values from an SMTBMC VCD, independently of logs."""
    names: dict[str, str] = {}
    scope: list[str] = []
    values: dict[str, int | None] = {}
    samples: dict[int, dict] = {}

    def snapshot() -> None:
        step = values.get("smt_step")
        if step is not None:
            samples[step] = {"step": step, **{k: v for k, v in values.items() if k != "smt_step"}}

    for line in path.read_text().splitlines():
        parts = line.split()
        if line.startswith("$scope"):
            scope.append(parts[2])
        elif line.startswith("$upscope"):
            scope.pop()
        elif line.startswith("$var"):
            if scope == [top] or (not scope and parts[4] == "smt_step"):
                names[parts[3]] = parts[4]
        elif line.startswith("#"):
            snapshot()
        elif line.startswith("b") and len(parts) == 2:
            if (name := names.get(parts[1])) is not None:
                bits = parts[0][1:]
                values[name] = int(bits, 2) if set(bits) <= {"0", "1"} else None
        elif line and line[0] in "01xz" and line[1:] in names:
            values[names[line[1:]]] = int(line[0]) if line[0] in "01" else None
    snapshot()
    return [samples[k] for k in sorted(samples)]


def validate_witness(case: dict, traces: list[Path]) -> dict:
    """Require the intended counterexample/cover conditions in actual VCD data."""
    kind = case.get("witness")
    if not kind:
        return {"status": "NOT_APPLICABLE", "reason": "successful safety proof has no counterexample"}
    top = {"shell": "shell_small_formal", "csr": "csr_control_formal", "axi": "axi_kernel_formal"}[case["family"]]
    found: dict[str, dict] = {}
    for trace in traces:
        samples = vcd_states(trace, top)
        for previous, current in zip(samples, samples[1:]):
            if kind == "negative" and previous.get("reset") == 0 and current.get("reset") == 0:
                if (previous.get("csr_req_valid") == 1 and previous.get("csr_req_ready") == 1
                        and previous.get("csr_req_addr") == 5 and current.get("csr_resp_valid") == 1
                        and current.get("csr_resp_rdata") == 4):
                    found["false_array_size_assertion"] = {"trace": str(trace), "before": previous, "after": current}
            if kind == "historical" and previous.get("reset") == 0 and current.get("reset") == 0:
                if (previous.get("csr_resp_valid") == 1 and previous.get("csr_resp_ready") == 0
                        and previous.get("csr_req_valid") == 1 and previous.get("csr_req_ready") == 1
                        and previous.get("csr_req_write") == 0 and previous.get("csr_req_addr") in (5, 6)
                        and current.get("csr_resp_valid") == 1
                        and current.get("csr_resp_rdata") in (4, 8)
                        and current["csr_resp_rdata"] != previous.get("csr_resp_rdata")):
                    found["csr_response_overwrite"] = {"trace": str(trace), "before": previous, "after": current}
            if kind == "irq_historical" and previous.get("ap_rst_n") == 1:
                mask = previous.get("f_irq_gie")
                pending = previous.get("f_irq_status")
                if mask in (0, 1) and pending in (0, 1) and current.get("interrupt") in (0, 1):
                    if current["interrupt"] != (mask & pending):
                        found["unregistered_irq_latency"] = {"trace": str(trace), "before": previous, "after": current}
        for current in samples:
            if kind == "csr_cover" and current.get("reset") == 0:
                if current.get("f_read_cover") == 3:
                    found["read_stall_consume"] = {"trace": str(trace), "step": current["step"]}
                if current.get("memreq_val") == 1 and current.get("memreq_rdy") == 0 and current.get("memreq_rw") == 0:
                    found["memory_request_stall"] = {"trace": str(trace), "step": current["step"]}
            if kind == "shell_cover" and current.get("rst_n") == 1:
                if current.get("out_valid") == 1 and current.get("out_ready") == 0:
                    found["output_stall"] = {"trace": str(trace), "step": current["step"]}
                if current.get("done") == 1 and current.get("f_output_seen") == 1:
                    found["output_then_done"] = {"trace": str(trace), "step": current["step"]}
            if kind == "axi_cover" and current.get("ap_rst_n") == 1:
                conditions = {
                    "read_a_address_stall": current.get("m_axi_gmem0_ARVALID") == 1 and current.get("m_axi_gmem0_ARREADY") == 0,
                    "read_b_address_stall": current.get("m_axi_gmem1_ARVALID") == 1 and current.get("m_axi_gmem1_ARREADY") == 0,
                    "write_address_stall_after_data": current.get("m_axi_gmem2_AWVALID") == 1 and current.get("m_axi_gmem2_AWREADY") == 0 and current.get("m_axi_gmem2_WVALID") == 0,
                    "write_data_stall_after_address": current.get("m_axi_gmem2_WVALID") == 1 and current.get("m_axi_gmem2_WREADY") == 0 and current.get("m_axi_gmem2_AWVALID") == 0,
                    "control_read_response_stall": current.get("s_axi_control_RVALID") == 1 and current.get("s_axi_control_RREADY") == 0,
                    "control_write_response_stall": current.get("s_axi_control_BVALID") == 1 and current.get("s_axi_control_BREADY") == 0,
                    "interrupt_asserted": current.get("interrupt") == 1,
                    "interrupt_mask_disable_latency": current.get("interrupt") == 1 and current.get("f_irq_gie") == 0 and current.get("f_irq_status") == 1,
                    "interrupt_acknowledged": current.get("f_irq_ack_cover") == 3,
                }
                for name, holds in conditions.items():
                    if holds:
                        found[name] = {"trace": str(trace), "step": current["step"]}
                previous = next((p for p in samples if p["step"] == current["step"] - 1), {})
                if (previous.get("ap_rst_n") == 1 and current.get("f_irq_busy") == 1
                        and current.get("f_irq_gie") in (0, 1) and previous.get("f_irq_gie") in (0, 1)
                        and current["f_irq_gie"] != previous["f_irq_gie"]):
                    found["interrupt_mask_changed_while_busy"] = {"trace": str(trace), "before": previous, "after": current}
        if kind == "csr_cover":
            for previous, current in zip(samples, samples[1:]):
                if (previous.get("reset") == 0 and current.get("reset") == 0
                        and all(previous.get(k) == 1 for k in ("csr_resp_valid", "csr_resp_ready", "csr_req_valid", "csr_req_ready"))
                        and previous.get("csr_req_addr") == 5
                        and current.get("csr_resp_valid") == 1 and current.get("csr_resp_rdata") == 4):
                    found["consume_and_replace"] = {"trace": str(trace), "step": current["step"]}
    required = {
        "negative": {"false_array_size_assertion"},
        "historical": {"csr_response_overwrite"},
        "irq_historical": {"unregistered_irq_latency"},
        "csr_cover": {"read_stall_consume", "memory_request_stall", "consume_and_replace"},
        "shell_cover": {"output_stall", "output_then_done"},
        "axi_cover": {"read_a_address_stall", "read_b_address_stall", "write_address_stall_after_data",
                      "write_data_stall_after_address", "control_read_response_stall", "control_write_response_stall",
                      "interrupt_asserted", "interrupt_mask_disable_latency", "interrupt_acknowledged",
                      "interrupt_mask_changed_while_busy"},
    }[kind]
    missing = sorted(required - found.keys())
    return {"status": "PASS" if not missing else "ERROR", "missing_conditions": missing, "evidence": found}


def cases() -> list[dict]:
    specs = [
        ("csr_reset_readback", "CHECK_RESET_READBACK", "prove", 6, None),
        ("csr_response_stability", "CHECK_CSR_HOLD", "prove", 6, None),
        ("csr_transaction_accounting", "CHECK_CSR_TRANSACTIONS", "prove", 6, None),
        ("memory_request_stability", "CHECK_MEMORY_HOLD", "prove", 6, None),
        ("csr_register_access_bounded", "CHECK_CSR_REGISTERS", "bmc", 12, None),
        ("csr_reachable_covers", "COVER_CONTROL", "cover", 16, "csr_cover"),
        ("negative_false_property", "NEGATIVE_CONTROL", "bmc", 6, "negative"),
        ("historical_csr_defect", "CHECK_CSR_HOLD -D READONLY_COUNTEREXAMPLE", "bmc", 6, "historical"),
    ]
    result = [{"name": n, "define": d, "mode": m, "depth": depth, "witness": w, "family": "csr"}
              for n, d, m, depth, w in specs]
    result += [
        {"name": "shell_1x1_protocol", "define": "CHECK_SHELL", "mode": "prove", "depth": 8, "family": "shell"},
        {"name": "shell_1x1_reachable_covers", "define": "COVER_SHELL", "mode": "cover", "depth": 24,
         "family": "shell", "witness": "shell_cover"},
        {"name": "axi_kernel_protocol", "define": "CHECK_AXI_KERNEL", "mode": "prove", "depth": None,
         "family": "axi", "engine": "abc pdr"},
        {"name": "axi_kernel_reachable_covers", "define": "COVER_AXI_KERNEL", "mode": "cover", "depth": 32,
         "family": "axi", "witness": "axi_cover"},
        {"name": "historical_unregistered_irq", "define": "CHECK_AXI_IRQ_ONLY", "mode": "bmc", "depth": 20,
         "family": "axi", "witness": "irq_historical"},
    ]
    return result


def sby_config(case: dict, snapshot: Path, seed: int, timeout: int) -> str:
    # SBY's [files] section splits on whitespace, so use paths relative to the
    # invocation cwd even when the requested output directory contains spaces.
    rtl = Path("sources/rtl")
    checkers = Path("sources/checkers")
    if case["family"] == "shell":
        script = f"""plugin -i slang
read_slang --top shell_small_formal -D {case['define']} -I rtl/cornell -I rtl/cornell/systolic rtl/cornell/systolic/SysBase.v rtl/mmul_row_sdp_ram.sv rtl/mmul_sysbase_core.sv rtl/mmul_sysbase_axis_shell.sv shell_small_formal.sv
opt_clean -purge
prep -top shell_small_formal"""
        files = f"rtl {rtl}\n{checkers / 'shell_small_formal.sv'}"
    elif case["family"] == "axi":
        script = f"""plugin -i slang
read_slang --top axi_kernel_formal -D {case['define']} mmul_sysbase.sv abstract_axis_shell.sv axi_kernel_formal.sv
opt_clean -purge
prep -top axi_kernel_formal"""
        kernel = checkers / "fixtures/mmul_sysbase_before_irq_register.sv" if case.get("witness") == "irq_historical" else Path("sources/hardware/mmul_sysbase.sv")
        files = f"mmul_sysbase.sv {kernel}\n{checkers / 'abstract_axis_shell.sv'}\n{checkers / 'axi_kernel_formal.sv'}"
    else:
        xcel = rtl / "mmul_sysbase_xcel.sv"
        if case.get("witness") == "historical":
            xcel = checkers / "fixtures/mmul_sysbase_xcel_before_csr_fix.sv"
        script = f"""read_verilog -formal -sv -D {case['define']} mmul_sysbase_xcel.sv abstract_axis_shell.sv csr_control_formal.sv
prep -top csr_control_formal"""
        files = f"mmul_sysbase_xcel.sv {xcel}\n{checkers / 'abstract_axis_shell.sv'}\n{checkers / 'csr_control_formal.sv'}"
    engine = case.get("engine", f"smtbmc z3 smt.random_seed={seed} sat.random_seed={seed}")
    depth = f"depth {case['depth']}\n" if case["depth"] is not None else ""
    return f"""[options]
mode {case['mode']}
{depth}timeout {timeout}
[engines]
{engine}
[script]
{script}
async2sync
dffunmap
[files]
{files}
"""


def run_formal(case: dict, output: Path, snapshot: Path, env: dict, tool_bin: Path, seed: int, timeout: int) -> dict:
    name = case["name"]
    config = output / "configs" / (name + ".sby")
    config.write_text(sby_config(case, snapshot, seed, timeout))
    job = output / "jobs" / name
    log = output / "logs" / (name + ".log")
    started = time.monotonic()
    # Keep SBY's own shell-generated workdir commands whitespace-free. The
    # parent process still runs inside the user's requested output directory.
    rc, timed_out = command([str(tool_bin / "sby"), "-f", "-d", f"jobs/{name}", f"configs/{name}.sby"],
                            output, env, log, timeout + 20)
    status_words = (job / "status").read_text().split() if (job / "status").exists() else []
    raw_status = status_words[0] if status_words else "ERROR"
    expected = "FAIL" if case.get("witness") in ("negative", "historical", "irq_historical") else "PASS"
    traces = sorted(job.glob("engine_*/trace*.vcd"))
    validation = validate_witness(case, traces) if raw_status == expected else {"status": "ERROR", "reason": "unexpected solver outcome"}
    validation_path = output / "logs" / (name + ".witness_validation.json")
    write_json(validation_path, validation)
    status = "PASS"
    if timed_out or raw_status in ("UNKNOWN", "ERROR", "TIMEOUT") or validation["status"] == "ERROR":
        status = "ERROR"
    elif raw_status != expected or rc != (2 if expected == "FAIL" else 0):
        status = "FAIL"
    # An actual failing property is a design failure, even without witness postprocessing.
    if raw_status == "FAIL" and expected == "PASS":
        status = "FAIL"
    scope = ("Unmodified complete SysBase/shell RTL; only the stated 1x1 configuration and protocol/reset safety."
             if case["family"] == "shell" else
             "Production mmul_sysbase_xcel CSR/scheduler RTL, ARRAY_SIZE=4/MAX_DIM=8; datapath outputs over-approximated.")
    assumptions = list(SHELL_ASSUMPTIONS if case["family"] == "shell" else CSR_ASSUMPTIONS)
    if case["family"] == "axi":
        scope = "Real packaged mmul_sysbase AXI kernel at production defaults; output AR/AW/W and AXI-Lite R/B hold/reset safety and exact one-cycle registered GIE/ISR interrupt/reset behavior; abstract datapath only."
        assumptions = list(AXI_ASSUMPTIONS)
        if case["mode"] == "cover":
            assumptions += ["Covers additionally require legal source payload hold, one outstanding memory response per accepted request, matching ID=0, OKAY responses and RLAST=1. These restrictions are not used by the safety proof."]
    if case.get("witness") == "historical":
        scope = "Historical pre-fix xcel snapshot only; expected defect counterexample, not production signoff."
        assumptions.append("For this defect witness only: read requests use valid CSR addresses 5 or 6.")
    if case.get("witness") == "irq_historical":
        scope = "Historical unregistered-IRQ wrapper snapshot only; expected temporal-contract failure, not an analog glitch simulation or production signoff."
    if case.get("witness") == "negative":
        scope += " Deliberately false ARRAY_SIZE==5 assertion; verifies the checking pipeline detects failure."
    strength = {"prove": "unbounded safety by induction if PASS", "bmc": "bounded check only; no unbounded claim",
                "cover": "existential reachability witnesses; not a universal correctness proof"}[case["mode"]]
    if case.get("engine") == "abc pdr":
        strength = "unbounded safety by property-directed reachability if PASS; no bounded depth limit"
    return {
        "name": name, "status": status, "engine_status": raw_status, "observed_status": raw_status, "expected_engine_status": expected,
        "kind": "negative_control" if expected == "FAIL" else case["mode"],
        "mode": case["mode"], "depth": case["depth"], "scope": scope, "strength": strength,
        "engine": case.get("engine", "smtbmc z3"), "solver_seed_applied": case.get("engine") != "abc pdr",
        "assumptions": assumptions, "abstracted_modules": [] if case["family"] == "shell" else ["mmul_sysbase_axis_shell"],
        "returncode": rc, "timed_out": timed_out, "elapsed_seconds": round(time.monotonic() - started, 3),
        "artifacts": {"configuration": str(config), "log": str(log), "work_dir": str(job),
                      "vcd": [str(p) for p in traces], "witnesses": [str(p) for p in sorted(job.glob('engine_*/trace*.yw'))],
                      "witness_validation": str(validation_path)},
    }


def replay(historical: bool, output: Path, snapshot: Path, env: dict, tool_bin: Path) -> dict:
    name = "historical_csr_replay" if historical else "corrected_csr_replay"
    job = output / "jobs" / name
    job.mkdir()
    rtl = snapshot / "rtl"
    checker = snapshot / "checkers"
    xcel = checker / "fixtures/mmul_sysbase_xcel_before_csr_fix.sv" if historical else rtl / "mmul_sysbase_xcel.sv"
    args = [str(tool_bin / "iverilog"), "-g2012", "-DSYNTHESIS", "-s", "csr_replay_tb",
            "-I", str(rtl / "cornell"), "-I", str(rtl / "cornell/systolic"), "-o", str(job / "test.vvp")]
    if historical:
        args.append("-DEXPECT_HISTORICAL_BUG")
    args += [str(rtl / p) for p in ("cornell/systolic/SysBase.v", "mmul_row_sdp_ram.sv", "mmul_sysbase_core.sv", "mmul_sysbase_axis_shell.sv")]
    args += [str(xcel), str(checker / "csr_replay_tb.sv")]
    compile_log = output / "logs" / (name + ".compile.log")
    run_log = output / "logs" / (name + ".log")
    rc, timed_out = command(args, job, env, compile_log, 60)
    if rc == 0 and not timed_out:
        rc, timed_out = command([str(tool_bin / "vvp"), str(job / "test.vvp")], job, env, run_log, 30)
    marker = "PASS: historical CSR defect independently reproduced" if historical else "PASS: corrected CSR hold"
    passed = rc == 0 and not timed_out and run_log.exists() and marker in run_log.read_text()
    return {"name": name, "status": "PASS" if passed else ("ERROR" if timed_out else "FAIL"),
            "kind": "negative_control_replay" if historical else "directed_simulation",
            "scope": "Independent Icarus simulation of complete real 4x4/32-bit hierarchy; CSR-only scenario, no datapath abstraction.",
            "expectation": "Reproduce the historical overwrite defect" if historical else "Hold responses, consume-and-replace, accept blocked writes exactly once",
            "returncode": rc, "timed_out": timed_out,
            "artifacts": {"compile_log": str(compile_log), "log": str(run_log), "vcd": [str(job / "replay.vcd")]}}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--seed", type=int, default=1, help="solver heuristic seed; this is not random-stimulus coverage")
    parser.add_argument("--tool-prefix", type=Path)
    parser.add_argument("--timeout-seconds", type=int, default=90, help="per formal job timeout")
    args = parser.parse_args()
    output = args.output_dir.expanduser().resolve()
    if output.is_relative_to(HERE) or output.is_relative_to(PROJECT / "hardware/rtl/src"):
        print("ERROR: output directory must be outside the source trees being snapshotted", file=sys.stderr)
        return 2
    output.mkdir(parents=True, exist_ok=True)
    if any((output / name).exists() for name in ("result.json", "sources", "jobs", "configs")):
        print("ERROR: use a fresh output directory; existing evidence will not be overwritten", file=sys.stderr)
        return 2
    result = {"schema_version": 1, "stage": "formal", "status": "ERROR", "seed": args.seed,
              "solver_seed": args.seed % (2**31), "checks": [],
              "limitations": ["This pilot is not full arithmetic or all-parameter signoff.",
                              "CSR/scheduler safety uses an explicit datapath over-approximation.",
                              "Register read/write data checking is bounded to 12 sampled steps.",
                              "Full unabstracted SysBase protocol proofs cover the 1x1 configuration only.",
                              "Packaged AXI kernel proof covers hold/reset and registered interrupt behavior with an abstract datapath, not complete AXI or arithmetic signoff.",
                              "No CDC, timing, hardware or eventual-completion proof is claimed.",
                              "Writes to configuration while busy remain allowed by RTL; no policy is invented or assumed away."]}
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    try:
        if args.timeout_seconds < 1:
            raise ValueError("timeout-seconds must be positive")
        bootstrap_path = WORKSPACE / "verification/bootstrap_formal.py"
        spec = importlib.util.spec_from_file_location("u55c_bootstrap_formal", bootstrap_path)
        bootstrap = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(bootstrap)
        prefix = args.tool_prefix.expanduser().resolve() if args.tool_prefix else bootstrap.DEFAULT_PREFIX
        result["toolchain"] = bootstrap.doctor(prefix)
        env = bootstrap.environment(prefix)
        tool_bin = bootstrap.suite_bin(prefix)
        for directory in ("jobs", "configs", "logs", "sources"):
            (output / directory).mkdir()
        snapshot = output / "sources"
        shutil.copytree(PROJECT / "hardware/rtl/src", snapshot / "rtl")
        shutil.copytree(HERE, snapshot / "checkers", ignore=shutil.ignore_patterns("__pycache__"))
        (snapshot / "hardware").mkdir()
        shutil.copy2(PROJECT / "verification/hardware/kernel/mmul_sysbase.sv", snapshot / "hardware/mmul_sysbase.sv")
        provenance = json.loads((snapshot / "checkers/fixtures/provenance.json").read_text())
        fixture = snapshot / "checkers/fixtures/mmul_sysbase_xcel_before_csr_fix.sv"
        if digest(fixture) != provenance["sha256"]:
            raise RuntimeError("historical bug fixture does not match its recorded SHA-256")
        irq_provenance = json.loads((snapshot / "checkers/fixtures/irq_provenance.json").read_text())
        if digest(snapshot / "checkers/fixtures/mmul_sysbase_before_irq_register.sv") != irq_provenance["sha256"]:
            raise RuntimeError("historical IRQ fixture does not match its recorded SHA-256")
        manifest = {str(p.relative_to(snapshot)): digest(p) for p in sorted(snapshot.rglob("*")) if p.is_file()}
        write_json(output / "source_manifest.json", manifest)
        result["source_manifest"] = str(output / "source_manifest.json")
        for case in cases():
            check = run_formal(case, output, snapshot, env, tool_bin, result["solver_seed"], args.timeout_seconds)
            result["checks"].append(check)
            write_json(output / "result.json", result)
            print(f"{check['status']}: {check['name']} (mode={check['mode']}, engine={check['engine_status']})", flush=True)
        for historical in (True, False):
            check = replay(historical, output, snapshot, env, tool_bin)
            result["checks"].append(check)
            print(f"{check['status']}: {check['name']}", flush=True)
        statuses = {c["status"] for c in result["checks"]}
        result["status"] = "ERROR" if "ERROR" in statuses else "FAIL" if "FAIL" in statuses else "PASS"
        result["summary"] = {status: sum(c["status"] == status for c in result["checks"])
                             for status in ("PASS", "FAIL", "ERROR")}
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError, KeyboardInterrupt) as exc:
        stop_process()
        result["status"] = "ERROR"
        result["error"] = str(exc)
    write_json(output / "result.json", result)
    print(f"{result['status']}: {output / 'result.json'}", flush=True)
    return {"PASS": 0, "FAIL": 1, "ERROR": 2}[result["status"]]


if __name__ == "__main__":
    raise SystemExit(main())
