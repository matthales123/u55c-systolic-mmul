#!/usr/bin/env python3
"""Run the real UVM/XSim pilot and detector negative controls, without site services."""
from __future__ import annotations

import argparse
import functools
import hashlib
import html
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import time

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1]


@functools.lru_cache(maxsize=4)
def native_environment(bin_dir: str, tool: str) -> dict[str, str]:
    """Evaluate only AMD's installed loader setup; never source user shell config."""
    binary = Path(bin_dir)
    recipe = (binary / "loader").read_text()
    launch = 'RDI_EXEC_COMMANDS "${RDI_ARGS[@]}"'
    if launch not in recipe:
        raise RuntimeError("Unsupported AMD loader; cannot prepare a clean environment")
    before, after = recipe.rsplit(launch, 1)
    recipe = before + "printf '\\0MMUL_ENV_START\\0'; /usr/bin/env -0; exit 0\n" + after
    seed_environment = {
        "PATH": "/usr/bin:/bin", "LANG": "C.UTF-8", "HOME": str(Path.home()),
        "XILINX_VIVADO": str(binary.parent), "_RDI_NEEDS_PYTHON": "True",
        "RDI_USE_JDK21": "1", "XILINX_LOCAL_USER_DATA": "no",
    }
    captured = subprocess.check_output(
        ["/bin/bash", "-c", recipe, str(binary / "loader"), "-exec", tool],
        cwd="/tmp", env=seed_environment, timeout=20,
    )
    pieces = captured.split(b"\0MMUL_ENV_START\0", 1)
    if len(pieces) != 2:
        raise RuntimeError("AMD environment preparation failed")
    return dict(item.decode().split("=", 1) for item in pieces[1].split(b"\0") if b"=" in item)


def execute(argv: list[str], output: Path, label: str, timeout: int,
            bin_dir: Path, environment_tool: str) -> dict:
    environment = native_environment(str(bin_dir), environment_tool).copy()
    scratch = output / "tmp"
    scratch.mkdir(exist_ok=True)
    environment["TMPDIR"] = str(scratch)
    log_path = output / f"{label}.log"
    started = time.monotonic()
    timed_out = False
    with log_path.open("wb") as stream:
        process = subprocess.Popen(argv, cwd=output, env=environment,
                                   stdout=stream, stderr=subprocess.STDOUT,
                                   start_new_session=True)
        try:
            code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            os.killpg(process.pid, signal.SIGKILL)
            code = process.wait()
        except BaseException:
            # Direct CLI cancellation must not leave a detached EDA process behind.
            try:
                os.killpg(process.pid, signal.SIGTERM)
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            except ProcessLookupError:
                process.wait()
            raise
    return {"name": label, "command": argv, "returncode": code,
            "timed_out": timed_out, "seconds": round(time.monotonic() - started, 3),
            "log": str(log_path)}


def parse_metrics(log: str) -> dict:
    lines = re.findall(r"(?m)^MMUL_METRICS (.+)$", log)
    if len(lines) != 1 or "MMUL_TEST_COMPLETE" not in log:
        raise ValueError("Missing unique completed-test metrics; a partial run cannot pass")
    metrics = {}
    for key, value in re.findall(r"(\w+)=([\d.]+)", lines[0]):
        metrics[key] = float(value) if "." in value else int(value)
    return metrics


def report_tables(path: Path, class_name: str) -> list[list[list[str]]]:
    """Read the fixed, generated XCRG 2025.1 report tables without web dependencies."""
    content = path.read_text(errors="replace")
    tables = []
    for table in re.findall(r"<table\s+class=['\"]" + re.escape(class_name) +
                            r"['\"][^>]*>(.*?)</table>", content, re.S):
        rows = []
        for row in re.findall(r"<tr[^>]*>(.*?)</tr>", table, re.S):
            rows.append([" ".join(html.unescape(re.sub(r"<[^>]*>", " ", cell)).split())
                         for cell in re.findall(r"<t[dh][^>]*>(.*?)</t[dh]>", row, re.S)])
        tables.append(rows)
    return tables


def summarize_code_coverage(report_dir: Path, tool_log: str, rtl: Path) -> dict:
    code_report = report_dir / "codeCoverageReport"
    for name in ("dashboard.html", "files.html", "modules.html"):
        if not (code_report / name).is_file():
            raise RuntimeError(f"XCRG did not generate required code report {name}")
    scores = {("statement" if name == "Line" else name.lower()): float(value)
              for name, value in re.findall(r"(Line|Branch|Condition|Toggle) Coverage Score ([\d.]+)", tool_log)}
    if set(scores) != {"statement", "branch", "condition", "toggle"}:
        raise RuntimeError("XCRG did not report all four measured RTL coverage types")
    file_tables = report_tables(code_report / "files.html", "fileInfosTable")
    if len(file_tables) != 1:
        raise RuntimeError("Unsupported or missing XCRG file coverage table")
    files = []
    empty_metadata_files = []
    open_items = []
    names = {"total statements": "statement", "total branches": "branch",
             "total conditions": "condition", "total toggles variables": "toggle_variables"}
    for row in file_tables[0][1:]:
        if len(row) < 10 or not row[0].isdigit():
            raise RuntimeError("Malformed XCRG file row")
        source = Path(row[1]).resolve()
        if not source.is_relative_to(rtl):
            # XCRG retains a zero-module source-map entry for the precompiled
            # UVM library even after its module is explicitly excluded.
            if all(row[index] == "0" for index in (2, 3, 4, 5, 6, 7, 8, 9)):
                empty_metadata_files.append(row[1])
                continue
            raise RuntimeError(f"Code coverage report leaked counted non-DUT source into its scope: {source}")
        page = code_report / f"file{row[0]}.html"
        counts = {}
        for table in report_tables(page, "fileScoreTable"):
            if len(table) < 2 or not table[0]:
                continue
            key = names.get(table[0][0].lower())
            if key and len(table[1]) >= 3:
                total, covered, uncovered = map(int, table[1][:3])
                counts[key] = {"total": total, "covered": covered, "uncovered": uncovered}
            elif table[1] and table[1][0] == "Total Bits":
                total, covered = map(int, table[1][1:3])
                counts["toggle_transitions"] = {"total": total, "covered": covered,
                                               "uncovered": total - covered}
        files.append({"source": str(source), "report_file_id": int(row[0]),
                      "reported_path": row[1], "html": str(page), "counts": counts})
        for kind, count in counts.items():
            if count["uncovered"]:
                open_items.append({"source": str(source), "kind": kind,
                                   "uncovered": count["uncovered"], "html": str(page),
                                   "disposition": "OPEN: inspect annotated RTL; add stimulus or explicitly review reachability. No waiver applied."})
    represented = {Path(item["source"]).name for item in files}
    if not {"mmul_sysbase_core.sv", "mmul_sysbase_axis_shell.sv", "SysBase.v"}.issubset(represented):
        raise RuntimeError("Code coverage scope omitted required DUT RTL files")
    if sum(item["counts"].get("statement", {}).get("covered", 0) for item in files) == 0:
        raise RuntimeError("No executed RTL statements in the code coverage database")
    summary = {"source_run": "positive", "scope": str(rtl), "measured_percent": scores,
               "files": files, "open_items": open_items,
               "empty_excluded_metadata_files": empty_metadata_files,
               "dashboard": str(code_report / "dashboard.html"),
               "threshold": None,
               "note": "Native XCRG scores and file-record counts; detailed instance views remain in HTML. UVM, testbench, interface and Cornell simulation-only vc_Trace are explicitly excluded. Include-path aliases may create multiple native records for one resolved RTL file; native file IDs are retained."}
    (report_dir / "coverage_summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    text = ["Positive-run RTL code coverage (XCRG 2025.1)", "",
            "Statement / branch / condition / toggle measured percentages:",
            " / ".join(f"{scores[key]:.2f}%" for key in ("statement", "branch", "condition", "toggle")),
            "", "Scope: " + str(rtl), "Native annotated report: " + summary["dashboard"],
            "", "Open coverage items (no automatic waivers or blanket pass percentage):"]
    for item in open_items:
        text.append(f"- {item['source']}: {item['uncovered']} uncovered {item['kind']} entries; {item['html']}")
    if not open_items:
        text.append("No uncovered entries in the collected file tables; this does not establish exhaustive functional correctness.")
    text.extend(["", "XCRG 2025.1 does not emit native text code reports; this text is derived from its measured HTML count tables and score log."])
    (report_dir / "coverage_summary.txt").write_text("\n".join(text) + "\n")
    return summary


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--seed", type=int, default=381)
    parser.add_argument("--vivado-root", type=Path,
                        default=Path("/tools/Xilinx/2025.1/Vivado"))
    args = parser.parse_args()
    if not 1 <= args.seed <= 2147483646:
        parser.error("--seed must be 1..2147483646")
    output = args.output_dir.expanduser().resolve()
    if output.exists() and any(output.iterdir()):
        parser.error("--output-dir must be new or empty; existing artifacts are never reused")
    output.mkdir(parents=True, exist_ok=True)
    result = {"status": "ERROR", "stage": "uvm", "seed": args.seed,
              "tool": "AMD XSim/Vivado 2025.1; built-in UVM 1.2",
              "dut": "mmul_sysbase_axis_shell", "checks": [], "metrics": {},
              "evidence": [], "artifacts": {}, "commands": []}
    started = time.monotonic()
    previous_term_handler = signal.getsignal(signal.SIGTERM)
    def interrupt_run(signum, frame):
        raise KeyboardInterrupt(f"Received signal {signum}")
    signal.signal(signal.SIGTERM, interrupt_run)
    try:
        binary = args.vivado_root.resolve() / "bin"
        rtl = PROJECT / "hardware/rtl/src"
        cornell = rtl / "cornell"
        sources = [cornell / "systolic/SysBase.v", rtl / "mmul_row_sdp_ram.sv",
                   rtl / "mmul_sysbase_core.sv", rtl / "mmul_sysbase_axis_shell.sv",
                   HERE / "mmul_if.sv", HERE / "mmul_pkg.sv", HERE / "tb.sv"]
        hash_paths = sorted(set(sources + list(cornell.rglob("*.v")) + [HERE / "run.py"]))
        result["source_hashes"] = {
            str(path.relative_to(PROJECT)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in hash_paths
        }
        compile_args = [str(binary / "unwrapped/lnx64.o/xvlog"), "--sv", "-L", "uvm",
                        "-i", str(args.vivado_root.resolve() / "data/system_verilog/uvm_1.2"),
                        "-i", str(cornell)] + list(map(str, sources))
        coverage_scope = output / "coverage_scope.txt"
        # Instrument normally; apply the tested scope filter at report time.
        # Explicit module exclusions preserve all instantiated DUT/support RTL.
        coverage_scope.write_text("module -mmul_uvm_tb -mmul_if* -mmul_pkg -uvm_pkg -vc_Trace\n")
        elaborate_args = [str(binary / "unwrapped/lnx64.o/xelab"), "mmul_uvm_tb",
                          "-L", "uvm", "-s", "mmul_uvm", "-mt", "4",
                          "--timescale", "1ns/1ps", "--cov_db_dir", str(output / "coverage"),
                          "--cov_db_name", "mmul_uvm", "--cc_type", "sbct"]
        for label, argv, timeout in [("compile", compile_args, 120),
                                     ("elaborate", elaborate_args, 180)]:
            command = execute(argv, output, label, timeout, binary,
                              "xvlog" if label == "compile" else "xelab")
            result["commands"].append(command)
            log = Path(command["log"]).read_text(errors="replace")
            if label == "elaborate":
                version = re.search(r"Vivado Simulator v([^\s]+)", log)
                if version:
                    result["tool"] = f"AMD XSim/Vivado {version.group(1)}; built-in UVM 1.2"
            good = command["returncode"] == 0 and not command["timed_out"] and not re.search(r"(?m)^ERROR:", log)
            result["checks"].append({"name": label, "passed": good})
            if not good:
                raise RuntimeError(f"{label} failed; see {command['log']}")
        simulation_tcl = output / "run.tcl"
        simulation_tcl.write_text("run all\nwrite_xsim_coverage -cov_db_dir {" +
                                  str(output / "coverage") +
                                  "} -cov_db_name mmul_uvm\nquit\n")
        for label, plusarg in [("positive", None), ("negative_result", "CORRUPT_RESULT"),
                               ("negative_protocol", "BREAK_PROTOCOL")]:
            argv = [str(binary / "unwrapped/lnx64.o/xsim"), "mmul_uvm",
                    "-tclbatch", str(simulation_tcl), "-sv_seed", str(args.seed),
                    "-log", str(output / f"{label}.xsim.log")]
            if plusarg:
                argv += ["-testplusarg", plusarg]
            command = execute(argv, output, label, 180, binary, "xsim")
            result["commands"].append(command)
            log = Path(command["log"]).read_text(errors="replace")
            metrics = parse_metrics(log)
            result["metrics"][label] = metrics
            normal_finish = (command["returncode"] == 0 and not command["timed_out"]
                             and metrics["uvm_fatals"] == 0 and metrics["active"] == 0
                             and "MMUL_WATCHDOG_TIMEOUT" not in log)
            checks = {f"{label}_completed": normal_finish}
            if label == "positive":
                checks.update({
                    "68_complete_and_4_reset_aborted_operations": metrics["completed"] == 68 and metrics["aborted"] == 4,
                    "independent_reference_and_transfer_checks": metrics["words"] >= 1537 and metrics["mismatches"] == 0 and metrics["transfer_errors"] == 0,
                    "no_uvm_or_sva_errors": metrics["uvm_errors"] == 0 and metrics["sva_failures"] == 0,
                    "all_dimensions_patterns_signs_tiles": metrics["dimension_mask"] == 255 and metrics["pattern_mask"] == 127 and metrics["sign_mask"] == 15 and metrics["tile_mask"] == 15,
                    "all_reset_phases": metrics["reset_mask"] == 31,
                    "declared_functional_coverage": metrics["operation_coverage"] == 100.0 and metrics["reset_coverage"] == 100.0,
                    "observed_stalls_gaps_and_hold_checks": metrics["sink_stall_cycles"] > 0 and metrics["source_gap_cycles"] > 0 and metrics["hold_checks"] > 0,
                    "back_to_back_restart": metrics["back_to_back"] > 0,
                })
            elif label == "negative_result":
                checks["scoreboard_rejects_corrupted_observation"] = (
                    metrics["completed"] == 1 and metrics["mismatches"] == 1
                    and metrics["uvm_errors"] == 1 and metrics["transfer_errors"] == 0
                    and metrics["sva_failures"] == 0)
            else:
                checks["sva_rejects_unstable_stalled_output"] = (
                    metrics["completed"] == 1 and metrics["sva_failures"] > 0
                    and "MMUL_SVA_OUTPUT_HOLD" in log and metrics["transfer_errors"] == 0)
            result["checks"].extend({"name": name, "passed": value} for name, value in checks.items())
            coverage = output / "coverage"
            if coverage.exists():
                destination = output / f"{label}_coverage"
                shutil.copytree(coverage, destination, dirs_exist_ok=True)
        report_dir = output / "positive_code_coverage_report"
        report_dir.mkdir(exist_ok=True)
        code_databases = list((output / "positive_coverage").rglob("xsim.CCInfo"))
        if not code_databases or not all(path.stat().st_size for path in code_databases):
            raise RuntimeError("Positive RTL code coverage database was not generated")
        report_args = [str(binary / "unwrapped/lnx64.o/xcrg"),
                       "--cov_db_dir", str(output / "positive_coverage"),
                       "--cov_db_name", "mmul_uvm", "--report_dir", str(report_dir),
                       "--report_format", "all", "--ccExclusionFile", str(coverage_scope),
                       "--cc_instancescount", "1000"]
        report_command = execute(report_args, output, "positive_coverage_report", 120,
                                 binary, "xcrg")
        result["commands"].append(report_command)
        report_ok = report_command["returncode"] == 0 and not report_command["timed_out"]
        report_ok = report_ok and (report_dir / "codeCoverageReport/dashboard.html").is_file()
        report_log = Path(report_command["log"]).read_text(errors="replace")
        report_ok = report_ok and not re.search(r"(?im)^\s*Error\s*:", report_log)
        result["checks"].append({"name": "positive_rtl_code_coverage_report", "passed": report_ok})
        if not report_ok:
            raise RuntimeError(f"Code coverage reporting failed; see {report_command['log']}")
        code_summary = summarize_code_coverage(report_dir, report_log, rtl)
        result["checks"].append({"name": "nonempty_dut_code_coverage_scope_and_measured_counts", "passed": True})
        result["code_coverage"] = {
            "scope": str(rtl), "scope_file": str(coverage_scope),
            "types": ["statement", "branch", "condition", "toggle"],
            "source_run": "positive", "report_directory": str(report_dir),
            "threshold": None,
            "policy": "Measured RTL gaps are reported for review; no blanket code-coverage threshold or implicit waiver.",
            "measured_percent": code_summary["measured_percent"],
            "open_item_count": len(code_summary["open_items"]),
            "summary_json": str(report_dir / "coverage_summary.json"),
            "summary_text": str(report_dir / "coverage_summary.txt"),
            "dashboard": code_summary["dashboard"],
        }
        result["status"] = "PASS" if all(check["passed"] for check in result["checks"]) else "FAIL"
        result["evidence"] = [
            "Observed input transfers independently reconstruct A/B; a separate modular arithmetic model checks every output transfer.",
            "Functional coverage is scoped to declared dimensions, stimulus pattern labels, observed sign/tile/stall classes and reset phases; RTL statement/branch/condition/toggle coverage is reported separately.",
            "Positive regression covers 56 directed dimension/pattern combinations, 8 seeded random operations, and 4 reset-abort/recovery pairs.",
            "Negative controls perturb observation data and stalled-output protocol independently; DUT source is unchanged.",
            "This is simulation evidence, not formal proof, physical timing closure, CDC signoff, or hardware validation.",
            "Input hold assertions may be vacuous because this DUT accepts load data without backpressure; input_hold_checks exposes that count.",
        ]
    except KeyboardInterrupt as exc:
        result["error"] = f"Interrupted: {exc}"
    except Exception as exc:
        result["error"] = f"{type(exc).__name__}: {exc}"
    finally:
        signal.signal(signal.SIGTERM, previous_term_handler)
    result["duration_seconds"] = round(time.monotonic() - started, 3)
    result["artifacts"] = {"result": str(output / "result.json"),
                           "logs": [item["log"] for item in result["commands"]],
                           "coverage_directories": [str(path) for path in sorted(output.glob("*_coverage"))]}
    (output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"status": result["status"], "result": str(output / "result.json"),
                      "error": result.get("error"),
                      "failed_checks": [check["name"] for check in result["checks"] if not check["passed"]]}))
    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
