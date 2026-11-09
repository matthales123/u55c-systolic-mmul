#!/usr/bin/env python3
"""Read-only U55C readiness and fail-closed SysBase hardware validation."""
from __future__ import annotations

import argparse
import csv
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import random
import re
import signal
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
DESIGN_ID = "u55c_systolic_mmul.sysbase"
KERNEL = "mmul_sysbase"
ABI = "u55c_mmul_legacy_a_b_c_dim_v1"
XRT_SMI = Path("/opt/xilinx/xrt/bin/xrt-smi")
XCLBINUTIL = Path("/opt/xilinx/xrt/bin/xclbinutil")
STOP_SIGNAL = 0
REQUIRED_RTL = [
    "hardware/rtl/src/mmul_sysbase_axis_shell.sv",
    "hardware/rtl/src/mmul_sysbase_core.sv",
    "hardware/rtl/src/mmul_row_sdp_ram.sv",
    "verification/hardware/kernel/mmul_sysbase.sv",
] + ["hardware/rtl/src/cornell/systolic/" + name for name in
     ("SysBase.v", "MacNew.v", "IntMulBase.v")] + [
    "hardware/rtl/src/cornell/vc/" + name for name in
    ("trace.v", "muxes.v", "arithmetic.v", "regs.v", "queues.v", "regfiles.v")]


class GateFailure(Exception):
    pass


class ExecutionInterrupted(Exception):
    def __init__(self, number):
        self.number=number
        super().__init__("Execution interrupted by signal "+str(number))


def install_signal_handlers():
    def interrupted(number, _frame):
        global STOP_SIGNAL
        STOP_SIGNAL=number
    signal.signal(signal.SIGINT,interrupted)
    signal.signal(signal.SIGTERM,interrupted)


def stop_process_group(process):
    try:
        os.killpg(process.pid,signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=1)
    except subprocess.TimeoutExpired:
        pass
    # Kill remaining descendants even if their direct parent already exited.
    try:
        os.killpg(process.pid,signal.SIGKILL)
    except ProcessLookupError:
        pass
    process.wait()


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def identity(files: list[dict]) -> str:
    return hashlib.sha256(json.dumps(sorted(files, key=lambda f: f["path"]),
                                    sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def source_inventory() -> dict:
    files = []
    for directory in (ROOT / "hardware/rtl/src", ROOT / "host/cpp"):
        for path in sorted(directory.rglob("*")):
            if path.is_file() and (path.suffix in (".v", ".sv", ".vh", ".svh", ".cpp", ".hpp")
                                   or path.name == "CMakeLists.txt"):
                files.append({"path": str(path.relative_to(ROOT)), "sha256": digest(path)})
    for directory in (Path(__file__).parent / "kernel", Path(__file__).parent / "host"):
        for path in sorted(directory.glob("*")):
            if path.is_file() and path.suffix in (".sv", ".xml", ".tcl", ".py", ".cpp", ".json"):
                files.append({"path": str(path.relative_to(ROOT)), "sha256": digest(path)})
    return {"project_root": str(ROOT), "files": files, "sha256": identity(files)}


def run_command(command: list[str], output: Path, stem: str, timeout: int = 30) -> dict:
    """No shell interpolation; kill the whole process group if a job times out."""
    started = time.monotonic()
    if STOP_SIGNAL:
        raise ExecutionInterrupted(STOP_SIGNAL)
    log = output / (stem + ".log")
    with log.open("w") as stream:
        stream.write(json.dumps(command) + "\n")
        stream.flush()
        process = subprocess.Popen(command, stdout=stream, stderr=subprocess.STDOUT,
                                   cwd=output, start_new_session=True)
        timed_out = False
        try:
            while True:
                if STOP_SIGNAL:
                    raise ExecutionInterrupted(STOP_SIGNAL)
                remaining=timeout-(time.monotonic()-started)
                if remaining<=0:
                    timed_out=True
                    stop_process_group(process)
                    code=process.returncode
                    break
                try:
                    code=process.wait(timeout=min(0.2,remaining))
                    if STOP_SIGNAL:
                        raise ExecutionInterrupted(STOP_SIGNAL)
                    break
                except subprocess.TimeoutExpired:
                    continue
        except BaseException:
            stop_process_group(process)
            raise
    return {"command": command, "returncode": code, "timed_out": timed_out,
            "elapsed_s": round(time.monotonic() - started, 3), "log": str(log)}


def inspect_board(output: Path, bdf: str, stem: str) -> dict:
    destination = output / (stem + ".json")
    command = [str(XRT_SMI), "--batch", "examine", "--device", bdf,
               "--report", "platform", "dynamic-regions", "pcie-info", "error",
               "--format", "JSON", "--output", str(destination)]
    run = run_command(command, output, stem)
    if run["returncode"] != 0 or not destination.exists():
        return {"status": "ERROR", "reason": "XRT read-only examine failed", "run": run}
    devices = json.loads(destination.read_text()).get("devices", [])
    matching = [item for item in devices if item.get("device_id", "").lower() == bdf.lower()]
    if len(matching) != 1:
        return {"status": "ERROR", "reason": "Requested board absent from XRT report", "run": run}
    device = matching[0]
    loaded = [region.get("xclbin_uuid", "").lower()
              for region in device.get("dynamic_regions", [])]
    ready = device.get("device_status", "").upper() == "HEALTHY"
    return {"status": "PASS" if ready else "FAIL", "bdf": bdf,
            "device_status": device.get("device_status"), "loaded_xclbin_uuids": loaded,
            "compute_units": [cu for region in device.get("dynamic_regions", [])
                              for cu in region.get("compute_units", [])],
            "clocks": [clock for platform in device.get("platforms", [])
                       for clock in platform.get("clocks", {}).get("clocks", [])],
            "evidence": str(destination), "run": run,
            "scope": "Read-only health/identity; not a hardware correctness test"}


def inspect_xclbin(path: Path, output: Path, stem: str) -> dict:
    run = run_command([str(XCLBINUTIL), "--info", "--input", str(path)], output, stem)
    if run["returncode"] != 0:
        raise GateFailure("xclbinutil could not inspect " + str(path))
    content = Path(run["log"]).read_text()
    uuid = re.search(r"UUID \(xclbin\):\s*([a-fA-F0-9-]+)", content)
    kernels = re.search(r"^\s*Kernels:\s*(.*)$", content, re.M)
    platform = re.search(r"Platform VBNV:\s*(\S+)", content)
    if not uuid or not kernels:
        raise GateFailure("XCLBIN UUID or kernel metadata missing")
    clocks_path=output/(stem+"_clock_topology.json")
    clocks_run=run_command([str(XCLBINUTIL),"--input",str(path),"--dump-section",
                           "CLOCK_FREQ_TOPOLOGY:JSON:"+str(clocks_path)],output,stem+"_clocks")
    clocks={}
    if clocks_run["returncode"]==0 and clocks_path.is_file():
        clocks=json.loads(clocks_path.read_text()).get("clock_freq_topology",{})
    return {"path": str(path), "sha256": digest(path), "uuid": uuid.group(1).lower(),
            "kernels": re.findall(r"[A-Za-z_][A-Za-z_0-9]*", kernels.group(1)),
            "platform": platform.group(1) if platform else None, "run": run,
            "clock_topology":clocks,"clock_topology_evidence":str(clocks_path),"clocks_run":clocks_run}


def primary_clock(artifact: dict) -> dict:
    topology=artifact.get("clock_topology",{})
    clocks=topology.get("m_clock_freq",[])
    primary=[clock for clock in clocks if clock.get("m_name")=="DATA_CLK" and clock.get("m_type")=="DATA"]
    if int(topology.get("m_count",-1))!=len(clocks) or len(primary)!=1 or float(primary[0]["m_freq_Mhz"])!=150:
        raise GateFailure("XCLBIN primary DATA_CLK topology must specify exactly 150 MHz")
    return {"xclbin_name":"DATA_CLK","xclbin_type":"DATA","runtime_id":"DATA_CLK",
            "routed_clock":"clk_kernel_00_unbuffered_net","system_clock":"ulp_ucs_aclk_kernel_00",
            "expected_mhz":150,"mapping_scope":"Reviewed U55C platform primary kernel clock; KERNEL_CLK is secondary kernel_01"}


def runtime_clock_check(board: dict, artifact: dict) -> dict:
    mapping=primary_clock(artifact)
    actual=[clock for clock in board.get("clocks",[]) if clock.get("id")==mapping["runtime_id"]]
    observed=float(actual[0]["freq_mhz"]) if len(actual)==1 else None
    return dict(mapping,status="PASS" if observed==mapping["expected_mhz"] else "FAIL",
                observed_mhz=observed,scope="XRT-reported loaded clock configuration; not an independent frequency measurement")


def project_file(entry: dict) -> Path:
    raw = Path(entry["path"])
    path = (ROOT / raw).resolve()
    if raw.is_absolute() or not path.is_relative_to(ROOT):
        raise GateFailure("Provenance input must be a project-relative path: " + str(raw))
    if not path.is_file() or digest(path) != entry.get("sha256"):
        raise GateFailure("Provenance file missing or changed: " + str(raw))
    return path


def verify_provenance(path: Path, trusted_sha: str, artifact: dict, host: Path) -> dict:
    if not trusted_sha:
        sidecar = path.with_suffix(".sha256")
        if not sidecar.is_file():
            raise GateFailure("Build-generated provenance digest is missing")
        trusted_sha = sidecar.read_text().strip()
    if not re.fullmatch(r"[0-9a-fA-F]{64}", trusted_sha):
        raise GateFailure("Invalid build-generated provenance SHA256")
    if digest(path) != trusted_sha.lower():
        raise GateFailure("Provenance digest does not match the trusted build record")
    data = json.loads(path.read_text())
    if data.get("schema_version") != 1 or data.get("design_id") != DESIGN_ID:
        raise GateFailure("Build record does not identify the SysBase pilot")
    build = data["build"]
    producer = build["producer"]
    if producer.get("name") != "sysbase_kernel_build_v1":
        raise GateFailure("Record was not produced by the SysBase build driver")
    project_file(producer)
    if build.get("status") != "PASS" or build.get("target") != "hw":
        raise GateFailure("Build record must describe a successful actual hardware build")
    if not build.get("commands") or not build.get("tool_versions"):
        raise GateFailure("Build command and tool-version evidence is required")
    if data.get("kernel") != KERNEL or data.get("abi") != ABI:
        raise GateFailure("Wrong kernel or host ABI; existing HLS mmul is not SysBase")
    if artifact["kernels"] != [KERNEL]:
        raise GateFailure("XCLBIN kernel metadata does not identify the SysBase kernel")
    primary_clock(artifact)
    for field in ("sha256", "uuid"):
        if data["xclbin"].get(field, "").lower() != artifact[field]:
            raise GateFailure("XCLBIN " + field + " differs from the trusted build")
    if data["xclbin"].get("platform") != artifact["platform"]:
        raise GateFailure("XCLBIN platform differs from the trusted build")
    inputs = data["inputs"]
    paths = [item["path"] for item in inputs]
    if len(paths) != len(set(paths)) or not set(REQUIRED_RTL).issubset(paths):
        raise GateFailure("Build manifest omits SysBase inputs or contains duplicate paths")
    for item in inputs:
        project_file(item)
    if identity(inputs) != data.get("source_sha256"):
        raise GateFailure("Build input manifest digest mismatch")
    evidence = build.get("evidence", [])
    kinds = {item.get("kind") for item in evidence}
    if not {"rtl_xo", "build_log", "synthesis_hierarchy", "implementation_signoff", "axi_simulation", "package_qualification", "constraint_policy", "cdc_methodology_findings", "finalization_script"}.issubset(kinds):
        raise GateFailure("Build, hierarchy, routed signoff and AXI simulation evidence are required")
    for item in evidence:
        evidence_path = project_file(item)
        if item["kind"] == "synthesis_hierarchy":
            hierarchy = evidence_path.read_text()
            for module in ("mmul_sysbase_core", "systolic_SysBase"):
                if module not in hierarchy:
                    raise GateFailure("Synthesized hierarchy does not contain " + module)
        elif item["kind"] in ("implementation_signoff", "axi_simulation"):
            if json.loads(evidence_path.read_text()).get("status") != "PASS":
                raise GateFailure("Required evidence did not pass: " + item["kind"])
        elif item["kind"]=="package_qualification":
            if "Unpacked XO IP synthesis completed" not in evidence_path.read_text():
                raise GateFailure("Packaged IP portability qualification did not complete")
    implementation = build["implementation"]
    vendor_platform=implementation.get("vendor_static_platform",{})
    if vendor_platform.get("status")!="PASS":
        raise GateFailure("Current build lacks reviewed vendor static-platform identity")
    project_file(vendor_platform)
    frontend=implementation.get("frontend",{})
    if (frontend.get("status")!="PASS" or frontend.get("tool_errors")!=0 or
        frontend.get("critical_warning_review",{}).get("status")!="PASS"):
        raise GateFailure("Implementation clock/partition preflight or tool-error review did not pass")
    project_file({"path":frontend["log_path"],"sha256":frontend["log_sha256"]})
    slacks = [implementation.get("setup_wns_ns", -1), implementation.get("hold_whs_ns", -1),
              implementation.get("targeted_pcie_setup_slack_ns",-1),
              implementation.get("targeted_pcie_contract",{}).get("setup_slack_ns",-1),
              implementation.get("targeted_pcie_contract",{}).get("hold_slack_ns",-1)]
    if (implementation.get("status") != "PASS" or not all(math.isfinite(n) and n >= 0 for n in slacks)
        or implementation.get("drc_errors") != 0 or implementation.get("drc_critical_warnings") != 0
        or implementation.get("drc_default_settings_applied") is not True
        or implementation.get("drc_waivers_ignored") is not True
        or implementation.get("drc_factory_check_verified") is not True
        or not implementation.get("all_user_timing_constraints_met")
        or implementation.get("unreviewed_constraints") or implementation.get("unknown_constraint_categories")
        or implementation.get("unreviewed_findings")
        or implementation.get("bus_skew",{}).get("status")!="PASS"
        or implementation.get("targeted_pcie_contract",{}).get("status")!="PASS"
        or implementation.get("targeted_pcie_contract",{}).get("setup_cycles_start")!=4
        or implementation.get("targeted_pcie_contract",{}).get("hold_cycles_start")!=3
        or implementation.get("targeted_pcie_contract",{}).get("setup_paths",0)<1
        or implementation.get("targeted_pcie_contract",{}).get("hold_paths",0)<1
        or implementation.get("kernel_clock",{}).get("status")!="PASS"
        or implementation.get("kernel_partition_control",{}).get("status")!="PASS"
        or implementation.get("irq_boundary",{}).get("status")!="PASS"
        or implementation.get("irq_boundary",{}).get("model")!="registered_source_vendor_ingress_two_stage_sync_v1"
        or implementation.get("irq_boundary",{}).get("vendor_input_cut",{}).get("verified") is not True
        or implementation.get("runtime_clock_contract",{}).get("status")!="PASS"
        or implementation.get("runtime_clock_contract",{}).get("model")!="xrt_scalable_primary_clock_v1"
        or implementation.get("runtime_clock_contract",{}).get("prelaunch_program_clock_gate_required") is not True
        or abs(implementation.get("kernel_clock",{}).get("period_ns",0)-1000/150)>0.001
        or implementation.get("targeted_pcie_setup_paths")!=1
        or implementation.get("routing_errors") != 0):
        raise GateFailure("Routed implementation lacks complete passing signoff")
    snapshot = (ROOT / build["source_snapshot"]).resolve()
    if not snapshot.is_relative_to(ROOT):
        raise GateFailure("Build snapshot is outside the project")
    for item in build["procedure_inputs"]:
        recorded = (snapshot / item["path"]).resolve()
        if not recorded.is_relative_to(snapshot) or not recorded.is_file() or digest(recorded) != item["sha256"]:
            raise GateFailure("Immutable build snapshot changed: " + item["path"])
    build_directory=(ROOT/build["build_directory"]).resolve()
    if not build_directory.is_relative_to(ROOT):
        raise GateFailure("Build output directory is outside the project")
    phases=build["phase_artifacts"]
    if not {"clock_qualification","axi_test","host_build","package","package_qualification","link","toolchain",build["signoff_phase"]}.issubset(phases):
        raise GateFailure("Build phase output history is incomplete")
    for phase,files in phases.items():
        if not files:
            raise GateFailure("Build phase has no historical output hashes: "+phase)
        for name,expected in files.items():
            recorded=(build_directory/name).resolve()
            if not recorded.is_relative_to(build_directory) or not recorded.is_file() or digest(recorded)!=expected:
                raise GateFailure("Historical build artifact changed: "+phase+": "+name)
    if build.get("migration"):
        migration=build["migration"]
        project_file(migration)
        project_file({"path":migration["observer_path"],"sha256":migration["observer_sha256"]})
    host_record = data["host"]
    if not host.is_file() or digest(host) != host_record.get("sha256"):
        raise GateFailure("Host executable differs from the trusted build")
    host_sources = host_record["sources"]
    needed_host = {"verification/hardware/host/checked_host.cpp"}
    if not needed_host.issubset({item["path"] for item in host_sources}):
        raise GateFailure("Host source manifest is incomplete")
    for item in host_sources:
        project_file(item)
    if not host_record.get("build_command") or not host_record.get("tool_versions"):
        raise GateFailure("Host build provenance is incomplete")
    max_dim = data.get("parameters", {}).get("MAX_DIM")
    if not isinstance(max_dim, int) or not 1 <= max_dim <= 255:
        raise GateFailure("Trusted MAX_DIM must be an integer from 1 to 255")
    return {"status": "PASS", "record": str(path), "sha256": trusted_sha.lower(),
            "source_sha256": data["source_sha256"], "parameters": data["parameters"],
            "trust_basis": "Repository build driver, immutable input snapshot and build-generated digest; optional external CI digest",
            "record_data": data}


def verify_device_mapping(device):
    # The checked host accepts device indices. Refuse ambiguous multi-card mapping
    # before any programming, rather than discovering this after changing a card.
    boards = sorted(p.name for p in Path("/sys/bus/pci/drivers/xocl").glob("????:??:??.?")
                    if p.is_symlink())
    if boards != [device]:
        raise GateFailure("Existing host device-index mapping is only verified for one XRT board")


def runtime_clock_driver_check(contract):
    version=json.loads(Path("/opt/xilinx/xrt/version.json").read_text())
    actual={"xrt_version":version.get("BUILD_VERSION"),"xrt_commit":version.get("VERSION_HASH"),
        "xocl_version":Path("/sys/module/xocl/version").read_text().strip(),
        "xocl_srcversion":Path("/sys/module/xocl/srcversion").read_text().strip(),
        "xclmgmt_version":Path("/sys/module/xclmgmt/version").read_text().strip(),
        "xclmgmt_srcversion":Path("/sys/module/xclmgmt/srcversion").read_text().strip()}
    expected=contract.get("runtime_identity",{})
    return {"status":"PASS" if expected and actual==expected else "FAIL","expected":expected,"actual":actual,
        "scope":"Installed XRT and loaded xocl/xclmgmt identities must match the reviewed clock-programming contract"}


def execute_checked_cases(args, output, artifact, board, max_dim, result, runtime_contract):
    """Called under the board lock after provenance and initial board checks."""
    verify_device_mapping(args.device)
    result["checks"]["runtime_clock_driver"]=runtime_clock_driver_check(runtime_contract)
    if result["checks"]["runtime_clock_driver"]["status"]!="PASS":
        raise GateFailure("Runtime XRT/loaded driver differs from the reviewed clock-programming contract")
    if artifact["uuid"] not in board["loaded_xclbin_uuids"]:
        if not args.allow_program:
            raise GateFailure("Loaded UUID differs; --allow-program is required to replace it")
        result["hardware_programming_attempted"]=True
        result["hardware_execution_attempted"]=True
        result["device_may_have_changed"]=True
        programming=run_command([str(XRT_SMI),"--batch","program","--device",args.device,"--user",str(args.xclbin)],
                                output,"board_program",args.timeout)
        programmed=programming["returncode"]==0 and not programming.get("timed_out",False)
        result["checks"]["programming"]={"status":"PASS" if programmed else "FAIL","run":programming}
        if not programmed:raise GateFailure("Explicit XRT programming did not complete successfully")
        board=inspect_board(output,args.device,"board_post_program")
        result["checks"]["board_post_program"]=board
    if (board["status"]!="PASS" or artifact["uuid"] not in board["loaded_xclbin_uuids"] or
        not board.get("compute_units") or
        any("IDLE" not in cu.get("status",{}).get("bits_set",[]) for cu in board["compute_units"])):
        raise GateFailure("Pre-launch board health, exact UUID, or compute-unit idle state is invalid")
    result["checks"]["clock_pre_launch"]=runtime_clock_check(board,artifact)
    if result["checks"]["clock_pre_launch"]["status"]!="PASS":
        raise GateFailure("Primary clock is not the validated configuration before checked host launch")
    def note_launch():
        result["hardware_execution_attempted"]=True
        result["device_may_have_changed"]=True
    result["checks"]["correctness_and_benchmark"]=hardware_cases(args,output,max_dim,note_launch)
    result["hardware_executed"]=True


def hardware_cases(args, output: Path, max_dim: int, on_launch=lambda: None) -> dict:
    verify_device_mapping(args.device)
    dimensions = list(range(1, min(max_dim, 8) + 1))
    cases = []
    for dim in dimensions:
        for pattern in ("random_u8", "signed_edges"):
            name = f"dim_{dim}_{pattern}"
            csv_path = output / (name + ".csv")
            command = [str(args.host), "--mode", "hw", "--control", "legacy",
                       "--kernel", KERNEL, "--xclbin", str(args.xclbin), "--device", "0",
                       "--elements", str(dim * dim), "--iterations", str(args.iterations),
                       "--seed", str(args.seed), "--csv", str(csv_path)]
            if pattern == "signed_edges":
                rng = random.Random(args.seed + dim)
                values = [-2147483648, -65536, -1, 0, 1, 65535, 2147483647]
                matrices = [[rng.choice(values) for _ in range(dim * dim)] for _ in range(2)]
                for label, matrix in zip(("a", "b"), matrices):
                    matrix_path = output / (name + "_" + label + ".csv")
                    with matrix_path.open("w") as stream:
                        csv.writer(stream).writerows(matrix[i:i + dim] for i in range(0, len(matrix), dim))
                    command += ["--matrix-" + label + "-path", str(matrix_path)]
                a, b = matrices
                expected = [sum(a[i * dim + k] * b[k * dim + j] for k in range(dim)) & 0xffffffff
                            for i in range(dim) for j in range(dim)]
                (output / (name + "_expected_u32.json")).write_text(json.dumps(expected) + "\n")
            on_launch()
            run = run_command(command, output, name, args.timeout)
            rows = list(csv.DictReader(csv_path.open())) if csv_path.exists() else []
            ok = run["returncode"] == 0 and not run.get("timed_out",False) and len(rows) == args.iterations
            ok = ok and all(row.get("verify_ok") == "1" and row.get("mode") == "hw"
                            and row.get("kernel") == KERNEL and int(row["elements"]) == dim * dim
                            for row in rows)
            timing = {}
            if ok:
                for field in ("h2d_ms", "kernel_ms", "d2h_ms", "total_ms"):
                    samples = [float(row[field]) for row in rows]
                    if not all(math.isfinite(n) and n >= 0 for n in samples):
                        ok = False
                    timing[field] = sum(samples) / len(samples)
            cases.append({"name": name, "status": "PASS" if ok else "FAIL", "run": run,
                          "csv": str(csv_path), "rows": len(rows), "mean_ms": timing})
            if not ok:
                break
        if cases[-1]["status"] != "PASS":
            break
    return {"status": "PASS" if all(case["status"] == "PASS" for case in cases) else "FAIL",
            "cases": cases, "seed": args.seed,
            "correctness": "Checked host CPU matrix reference, output modulo 2^32, explicit kernel error register check",
            "benchmark_scope": "Host-measured transfer and launch/wait durations; includes first iteration; not FPGA cycle counts"}


def main() -> int:
    install_signal_handlers()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--device", default="0000:04:00.1")
    parser.add_argument("--xclbin", type=Path, help="Defaults beside explicit provenance, otherwise build/hardware/hw/mmul_sysbase.xclbin")
    parser.add_argument("--host", type=Path, help="Defaults to checked host beside the selected XCLBIN")
    parser.add_argument("--provenance", type=Path)
    parser.add_argument("--trusted-provenance-sha256")
    parser.add_argument("--execute-hardware", action="store_true",
                        help="Execute the verified host, which calls XRT load_xclbin and runs kernels")
    parser.add_argument("--allow-program", action="store_true",
                        help="With --execute-hardware, permit replacement of a different loaded XCLBIN")
    parser.add_argument("--iterations", type=int, default=3)
    parser.add_argument("--timeout", type=int, default=120)
    args = parser.parse_args()
    if not 0 <= args.seed <= 0xffffffff or not 1 <= args.iterations <= 1000 or args.timeout < 1:
        parser.error("seed must be uint32; iterations 1..1000; timeout positive")
    if not re.fullmatch(r"[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-7]", args.device):
        parser.error("--device must be a PCI BDF")
    args.device = args.device.lower()
    args.xclbin = (args.xclbin or (args.provenance.parent / "mmul_sysbase.xclbin" if args.provenance else
                    ROOT / "build/hardware/hw/mmul_sysbase.xclbin")).resolve()
    args.host = args.host.resolve() if args.host else args.xclbin.parent / "sysbase_checked_host"
    if args.provenance is None and args.xclbin.with_suffix(".provenance.json").is_file():
        args.provenance = args.xclbin.with_suffix(".provenance.json")
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    if any(output.iterdir()):
        parser.error("--output-dir must be empty to preserve run evidence")
    result = {"schema_version": 1, "stage": "hardware", "design_id": DESIGN_ID,
              "status": "SKIPPED", "seed": args.seed, "hardware_executed": False,
              "hardware_execution_attempted": False,
              "hardware_programming_attempted": False,
              "device_may_have_changed": False,
              "started_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
              "source_snapshot": {}, "runner_sha256": None, "runtime_xrt": {},
              "checks": {}, "artifact_inventory": []}
    try:
        result["source_snapshot"]=source_inventory()
        result["runner_sha256"]=digest(Path(__file__))
        version_file=Path("/opt/xilinx/xrt/version.json")
        result["runtime_xrt"]=json.loads(version_file.read_text()) if version_file.is_file() else {"available":False}
        result["checks"]["board_readiness"] = inspect_board(output, args.device, "board_before")
        for candidate in (ROOT / "build/hardware/hw/mmul.xclbin", ROOT / "build/hardware/hw/mmul_cmd.xclbin"):
            if candidate.exists():
                item = inspect_xclbin(candidate, output, "inventory_" + candidate.stem)
                item["eligible_for_sysbase_validation"] = False
                item["reason"] = "Legacy artifact inventory only; no trusted SysBase build provenance"
                result["artifact_inventory"].append(item)
        if not args.xclbin.is_file():
            result["reason"] = "No matching SysBase hardware artifact: " + str(args.xclbin)
        elif not args.provenance:
            raise GateFailure("Selected artifact has no trusted SysBase build provenance; filename is insufficient")
        else:
            artifact = inspect_xclbin(args.xclbin, output, "selected_xclbin")
            result["selected_artifact"] = artifact
            provenance = verify_provenance(args.provenance.resolve(), args.trusted_provenance_sha256,
                                           artifact, args.host)
            result["checks"]["provenance"] = {k: v for k, v in provenance.items() if k != "record_data"}
            if not args.execute_hardware:
                result["reason"] = "Read-only checks complete; hardware execution was not requested"
            else:
                lock_path = Path(__file__).parent / (".board_" + args.device.replace(":", "_") + ".lock")
                with lock_path.open("a") as lock:
                    try:
                        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    except BlockingIOError:
                        raise GateFailure("Another pilot hardware validation holds the board lock")
                    # Recheck identity inside the lock, immediately before executing the host.
                    board = inspect_board(output, args.device, "board_pre_execute")
                    result["checks"]["board_pre_execute"] = board
                    if board["status"] != "PASS":
                        raise GateFailure("Board is not healthy and ready")
                    if any("IDLE" not in cu.get("status",{}).get("bits_set",[]) for cu in board["compute_units"]):
                        raise GateFailure("A loaded compute unit is busy or its idle state is unknown")
                    verify_provenance(args.provenance.resolve(), args.trusted_provenance_sha256,
                                      inspect_xclbin(args.xclbin, output, "xclbin_pre_execute"), args.host)
                    execute_checked_cases(args,output,artifact,board,provenance["parameters"]["MAX_DIM"],result,
                        provenance["record_data"]["build"]["implementation"].get("runtime_clock_contract",{}))
                    result["checks"]["board_after"] = inspect_board(output, args.device, "board_after")
                    result["checks"]["clock_after"] = runtime_clock_check(result["checks"]["board_after"],artifact)
                    result["status"] = result["checks"]["correctness_and_benchmark"]["status"]
                    if result["status"]!="PASS":
                        result["board_recheck_required"]=True
                        result["hardware_quiescence_verified"]=False
                    if (result["checks"]["board_after"]["status"] != "PASS" or
                        result["checks"]["clock_after"]["status"]!="PASS" or
                        artifact["uuid"] not in result["checks"]["board_after"].get("loaded_xclbin_uuids", []) or
                        any("IDLE" not in cu.get("status",{}).get("bits_set",[]) for cu in result["checks"]["board_after"]["compute_units"])):
                        result["status"] = "FAIL"
                        result["reason"] = "Post-run board health, loaded identity, primary clock or compute-unit idle state did not match expectations"
                        result["board_recheck_required"]=True
    except ExecutionInterrupted as error:
        result["status"]="INCOMPLETE"
        result["signal"]=error.number
        result["reason"]=str(error)
        result["board_recheck_required"]=result["hardware_execution_attempted"]
        result["hardware_quiescence_verified"]=False
    except GateFailure as error:
        result["status"] = "FAIL"
        result["reason"] = str(error)
    except (OSError, ValueError, KeyError, TypeError) as error:
        result["status"] = "ERROR"
        result["reason"] = str(error)
    if STOP_SIGNAL and result["status"]!="INCOMPLETE":
        result.update(status="INCOMPLETE",signal=STOP_SIGNAL,reason="Execution interrupted by signal "+str(STOP_SIGNAL),
                      board_recheck_required=result["hardware_execution_attempted"],hardware_quiescence_verified=False)
    if result["hardware_execution_attempted"] and result["status"]!="PASS":
        result["board_recheck_required"]=True
        result["hardware_quiescence_verified"]=False
    result["finished_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    (output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"status": result["status"], "reason": result.get("reason"),
                      "hardware_executed": result["hardware_executed"], "result": str(output / "result.json")}))
    return (128+result["signal"]) if "signal" in result else (0 if result["status"] in ("PASS", "SKIPPED") else 1)


if __name__ == "__main__":
    raise SystemExit(main())
