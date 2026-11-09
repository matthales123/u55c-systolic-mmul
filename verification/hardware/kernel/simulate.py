#!/usr/bin/env python3
"""Run the SysBase XRT wrapper against stalled AXI memory/control models."""
import argparse
import importlib.util
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[3]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    spec = importlib.util.spec_from_file_location("pilot_xsim", ROOT / "verification/uvm/run.py")
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)
    bin_dir = Path("/tools/Xilinx/2025.1/Vivado/bin")
    rtl = ROOT / "hardware/rtl/src"
    here = Path(__file__).resolve().parent
    sources = [rtl / "cornell/systolic/SysBase.v", rtl / "mmul_row_sdp_ram.sv",
               rtl / "mmul_sysbase_core.sv", rtl / "mmul_sysbase_axis_shell.sv",
               here / "mmul_sysbase.sv", here / "mmul_sysbase_axi_tb.sv"]
    commands = [
        ("compile", [str(bin_dir / "unwrapped/lnx64.o/xvlog"), "--sv", "-i", str(rtl / "cornell")] + list(map(str,sources)), "xvlog"),
        ("elaborate", [str(bin_dir / "unwrapped/lnx64.o/xelab"), "mmul_sysbase_axi_tb", "-a", "-s", "sysbase_axi", "-mt", "4", "--timescale", "1ns/1ps"], "xelab"),
        ("simulate", [str(output / "xsim.dir/sysbase_axi/axsim"), "-runall"], "xsim"),
    ]
    result = {"status": "ERROR", "stage": "axi_wrapper_simulation", "commands": []}
    for label, command, tool in commands:
        run = helper.execute(command, output, label, 180, bin_dir, tool)
        result["commands"].append(run)
        text = Path(run["log"]).read_text(errors="replace")
        if run["returncode"] or run["timed_out"] or re.search(r"(?m)^(ERROR:|Fatal:|FATAL:)", text):
            result["reason"] = label + " failed"
            break
        if label == "simulate":
            passed = re.search(r"SYSBASE_AXI_TEST_PASS tests=(\d+) cycles=(\d+) writes=(\d+)", text)
            if passed and int(passed[1]) >= 12:
                result.update(status="PASS", tests=int(passed[1]), cycles=int(passed[2]), writes=int(passed[3]))
            else:
                result["status"] = "FAIL"
                result["reason"] = "Missing completed AXI test marker"
    if result["status"] == "PASS":
        negative = helper.execute([str(output / "xsim.dir/sysbase_axi/axsim"), "-runall",
                                   "-testplusarg", "CORRUPT_AXI_OUTPUT"], output,
                                  "negative_output_corruption", 180, bin_dir, "xsim")
        result["commands"].append(negative)
        negative_log = Path(negative["log"]).read_text(errors="replace")
        result["negative_control_detected"] = "Mismatch dim=" in negative_log and "SYSBASE_AXI_TEST_PASS" not in negative_log
        if not result["negative_control_detected"]:
            result["status"] = "FAIL"
            result["reason"] = "Output-corruption negative control was not detected"
    (output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result))
    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
