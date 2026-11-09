#!/usr/bin/env python3
"""Negative controls for artifact provenance; these never access the FPGA."""
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
from types import SimpleNamespace
import zipfile

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location("hardware_gate",HERE/"run.py")
gate=importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)
build_spec=importlib.util.spec_from_file_location("hardware_build",HERE/"kernel/build.py")
builder=importlib.util.module_from_spec(build_spec)
build_spec.loader.exec_module(builder)


def setUpModule():
    (HERE / "results").mkdir(exist_ok=True)


def irq_fixture():
    source="level0_i/ulp/mmul_sysbase_1/inst/interrupt_reg"
    stages=["level0_i/ii_level0_pipe/inst/pxi_ii_core/inst/ip_irq_cu_00/inst/q_i_reg[1]"]+[
        "level0_i/blp/blp_i/PLP/ss_ert/inst/user_peripherals/intc_hierarchy/axi_intc_cu_bank_00/U0/INTC_CORE_I/"
        f"INTR_DETECT_GEN[1].ASYNC_GEN.intr_ff_reg[{index}]" for index in (0,1)]
    connections=[];previous=source+"/Q"
    for index,stage in enumerate(stages):
        connections.append({"from_pin":previous,"to_pin":stage+"/D","fanin_pins":[previous],
            "fanin_startpoints":[previous.rsplit("/",1)[0]+"/C"],
            "net_segments":["interrupt_net_"+str(index)],"destination_on_source_net":1,
            "exception_selector_intersection":["level0_i/ulp/irq/lp_s_irq_cu_00"] if index==0 else [],
            "timing":{kind:{"count":1,"slack_ns":None if index==1 else 0.1,"properties":{"STARTPOINT_PIN":previous.rsplit("/",1)[0]+"/C",
                "ENDPOINT_PIN":stage+"/D","STARTPOINT_CLOCK":"dma_ip_axi_aclk_1","ENDPOINT_CLOCK":"dma_ip_axi_aclk_1",
                "EXCEPTION":"False Path" if index==1 else "","SLACK":"" if index==1 else "0.1","LOGIC_LEVELS":"0",
                "DELAY_TYPE":"max" if kind=="setup" else "min"}} for kind in ("setup","hold")}})
        previous=stage+"/Q"
    return {"registered_source":{"output_pin":"level0_i/ulp/mmul_sysbase_1/inst/interrupt",
        "source_pins":[source+"/Q"],"source_cells":[source],"timing_startpoints":[source+"/C"],
        "output_on_source_net":1},"destination_stages":stages,"connections":connections,
        "cells":[{"name":name,"clocks":"clk_kernel_00_unbuffered_net" if index==0 else "dma_ip_axi_aclk_1",
            "properties":{"REF_NAME":"FDRE","ASYNC_REG":"TRUE" if index>=2 else "FALSE"}}
            for index,name in enumerate([source]+stages)]}


class ProvenanceTests(unittest.TestCase):
    def test_primary_runtime_clock_uses_data_not_secondary_kernel_label(self):
        artifact={"clock_topology":{"m_count":"3","m_clock_freq":[
            {"m_name":"DATA_CLK","m_type":"DATA","m_freq_Mhz":"150"},
            {"m_name":"KERNEL_CLK","m_type":"KERNEL","m_freq_Mhz":"500"},
            {"m_name":"hbm_aclk","m_type":"SYSTEM","m_freq_Mhz":"450"}]}}
        board={"clocks":[{"id":"DATA_CLK","freq_mhz":"150"},{"id":"KERNEL_CLK","freq_mhz":"500"}]}
        self.assertEqual(gate.runtime_clock_check(board,artifact)["status"],"PASS")
        board["clocks"][0]["freq_mhz"]="300"
        self.assertEqual(gate.runtime_clock_check(board,artifact)["status"],"FAIL")
        board["clocks"].pop(0)
        self.assertEqual(gate.runtime_clock_check(board,artifact)["status"],"FAIL")
        artifact["clock_topology"]["m_clock_freq"][0]["m_freq_Mhz"]="300"
        with self.assertRaisesRegex(gate.GateFailure,"150 MHz"):
            gate.primary_clock(artifact)

    def test_manifest_identity_is_order_independent(self):
        records=[{"path":"b.sv","sha256":"b"},{"path":"a.sv","sha256":"a"}]
        self.assertEqual(gate.identity(records),gate.identity(list(reversed(records))))
        changed=[dict(item) for item in records];changed[0]["sha256"]="different"
        self.assertNotEqual(gate.identity(records),gate.identity(changed))

    def test_paths_cannot_escape_project(self):
        with self.assertRaisesRegex(gate.GateFailure,"project-relative"):
            gate.project_file({"path":"../../../../etc/passwd","sha256":"irrelevant"})

    def test_changed_source_rejected(self):
        with self.assertRaisesRegex(gate.GateFailure,"missing or changed"):
            gate.project_file({"path":gate.REQUIRED_RTL[0],"sha256":"0"*64})

    def record(self,root,record):
        path=root/"renamed_sysbase.provenance.json"
        path.write_text(json.dumps(record))
        return path,gate.digest(path)

    def test_tampered_provenance_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path,sha=self.record(Path(directory),{})
            path.write_text('{"tampered":true}')
            with self.assertRaisesRegex(gate.GateFailure,"digest"):
                gate.verify_provenance(path,sha,{},Path("missing"))

    def test_renamed_hls_kernel_rejected_even_with_matching_uuid(self):
        producer={"name":"sysbase_kernel_build_v1","path":"verification/hardware/kernel/build.py",
                  "sha256":gate.digest(HERE/"kernel/build.py")}
        record={"schema_version":1,"design_id":gate.DESIGN_ID,"kernel":gate.KERNEL,"abi":gate.ABI,
                "build":{"producer":producer,"status":"PASS","target":"hw","commands":["example"],"tool_versions":{"vivado":"2025.1"}}}
        with tempfile.TemporaryDirectory() as directory:
            path,sha=self.record(Path(directory),record)
            artifact={"kernels":["mmul"],"uuid":"cf1bc83b-8474-5a38-cdf9-881079db4f78"}
            with self.assertRaisesRegex(gate.GateFailure,"kernel metadata"):
                gate.verify_provenance(path,sha,artifact,Path("missing"))

    def test_sidecar_missing_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path,_=self.record(Path(directory),{})
            with self.assertRaisesRegex(gate.GateFailure,"digest is missing"):
                gate.verify_provenance(path,None,{},Path("missing"))



def synthetic_check_timing_report():
    """Construct parser input for unit tests; this is not a hardware result."""
    sections = [
        ("no_clock", []), ("constant_clock", []), ("pulse_width_clock", []),
        ("unconstrained_internal_endpoints", []),
        ("no_input_delay", ["io_data_satellite_ctrl_00[0]", "io_data_satellite_ctrl_00[1]",
            "io_data_satellite_ctrl_00[2]", "io_data_satellite_ctrl_00[3]",
            "io_perst_n_00[0]", "io_uart_cmc_00_rxd", "io_uart_satellite_ctrl_00_rxd"]),
        ("no_output_delay", ["io_hbm_cattrip_00[0]", "io_uart_cmc_00_txd", "io_uart_satellite_ctrl_00_txd"]),
        ("multiple_clock", []), ("generated_clocks", []), ("loops", []),
        ("partial_input_delay", []), ("partial_output_delay", []), ("latch_loops", []),
    ]
    return "SYNTHETIC UNIT TEST INPUT\n\n" + "\n".join(
        f"{number}. checking {name} ({len(ports)})\n------------------------\n"
        + "\n".join(ports) + "\n"
        for number, (name, ports) in enumerate(sections, 1)
    )


class SignoffTests(unittest.TestCase):
    def test_finding_identity_ignores_only_report_numbering(self):
        original={"kind":"cdc","properties":{"NAME":"CDC-2#1","ID":"1","CHECK":"CDC-2",
            "SEVERITY":"Warning","STARTPOINT_PIN":"vendor/source/C","ENDPOINT_PIN":"vendor/destination/D"}}
        renumbered=json.loads(json.dumps(original));renumbered["properties"].update(NAME="CDC-2#73",ID="73")
        self.assertEqual(builder.finding_signature(original),builder.finding_signature(renumbered))
        renumbered["properties"]["ENDPOINT_PIN"]="application/destination/D"
        self.assertNotEqual(builder.finding_signature(original),builder.finding_signature(renumbered))

    def setUp(self):
        (HERE/"results").mkdir(exist_ok=True)
        self.temporary=tempfile.TemporaryDirectory(dir=HERE/"results")
        self.directory=Path(self.temporary.name)
        self.report=synthetic_check_timing_report()
        # Unit tests exercise the unmodified production gate using generated evidence.
        # The real policy and its private hardware proof bundle are never altered.
        policy = json.loads((HERE / "kernel/constraint_policy.json").read_text())
        self.synthetic_evidence = self.directory / "synthetic_review_evidence.txt"
        self.synthetic_evidence.write_text("Synthetic unit-test evidence; not hardware signoff.\n")
        policy["review_evidence"] = [{"path": str(self.synthetic_evidence.relative_to(builder.ROOT)),
                                      "sha256": builder.sha(self.synthetic_evidence)}]
        irq_contract = policy["irq_input_cut"]
        synthetic_irq = self.directory / "synthetic_irq_input_cut.xdc"
        synthetic_irq.write_text("# Synthetic unit-test input, not vendor evidence.\n"
            + "current_instance " + irq_contract["scoped_instance"] + "\n"
            + "set_property src_info {type:SCOPED_XDC file:131 line:47 export:INPUT save:NONE read:READ} [current_design]\n"
            + irq_contract["constraint"] + "\n")
        irq_contract["source"] = {"path": str(synthetic_irq.relative_to(builder.ROOT)),
                                  "sha256": builder.sha(synthetic_irq)}
        policy_directory = self.directory / "synthetic_policy"
        policy_directory.mkdir()
        (policy_directory / "constraint_policy.json").write_text(json.dumps(policy))
        policy_patch = patch.object(builder, "HERE", policy_directory)
        policy_patch.start()
        self.addCleanup(policy_patch.stop)
        self.metadata="Platform VBNV: xilinx_u55c_gen3x16_xdma_3_202210_1\nStatic UUID: b7ac1abe-1e3e-1cb6-86d5-a81232452676\n"
        self.metadata+="Name: DATA_CLK\nIndex: 2\nType: DATA\nFrequency: 150 MHz\nName: ulp_ucs_aclk_kernel_00\nType: SCALABLE\nDefault Freq: 300 MHz\nRequested Freq: 150 MHz\nAchieved Freq: 150 MHz\n"
        (self.directory/"metrics.json").write_text(json.dumps({"setup_wns_ns":0.1,"hold_whs_ns":0.01,
            "drc_errors":0,"drc_critical_warnings":0,"targeted_pcie_setup_paths":1,"targeted_pcie_setup_slack_ns":0.1,
            "drc_default_settings_applied":True,"drc_waivers_ignored":True,
            "tool":{"vivado_version":"2025.1","vivado_sw_build":"6140274"}}))
        (self.directory/"timing_summary.rpt").write_text("All user specified timing constraints are met.\n")
        (self.directory/"route_status.rpt").write_text("# of nets with routing errors.......... : 0 :\n")
        (self.directory/"bus_skew.rpt").write_text("Slack (MET) : 0.100ns\n")
        (self.directory/"violations.json").write_text("[]\n")
        (self.directory/"drc_checks.json").write_text(json.dumps([{"name":"HDPR-5","default_severity":"Error",
            "effective_severity":"Warning","default_enabled":1,"effective_enabled":1}]))
        (self.directory/"irq_structure.json").write_text(json.dumps(dict(irq_fixture(),kernel_partition_control={"count":1,
            "name":"level0_i/ulp/mmul_sysbase_1/inst","orig_ref_name":"mmul_sysbase",
            "ref_name":"ulp_mmul_sysbase_1_0_mmul_sysbase","dont_partition":1})))
        (self.directory/"clocks.rpt").write_text("clk_kernel_00_unbuffered_net 6.667 {0.000 3.333} P,G,A {kernel_clock_output}\n")
        source="level0_i/blp/blp_i/ss_hif/inst/pcie/inst/bd_39ab_pcie_0_pcie_4_0_pipe_inst/pcie_4_c_e4_inst/CORECLK"
        destination="level0_i/blp/blp_i/PLP/ss_dma/inst/dma/inst/chain_cfg_phy_link_down/with_ff_chain.ff_chain_gen[0].sync_rst.ff_chain_reg[1][0]/D"
        (self.directory/"targeted_pcie_timing.rpt").write_text("\n".join(
            f"Slack (MET) : 0.100ns\nSource: {source}\nDestination: {destination}\nPath Type: {kind}\n"
            "Timing Exception: MultiCycle Path Setup -start 4 Hold -start 3\n" for kind in ("Setup","Hold")))

    def tearDown(self):self.temporary.cleanup()

    def evaluate(self,report=None,metadata=None):
        (self.directory/"check_timing.rpt").write_text(report if report is not None else self.report)
        return builder.signoff_status(self.directory,metadata if metadata is not None else self.metadata)

    def test_changed_synthetic_review_evidence_is_rejected(self):
        self.synthetic_evidence.write_text("tampered")
        with self.assertRaisesRegex(RuntimeError, "Vendor finding review evidence changed"):
            self.evaluate()

    def test_exact_static_shell_ports_are_scoped_exceptions(self):
        result=self.evaluate()
        self.assertEqual(result["status"],"PASS")
        self.assertEqual(len(result["reviewed_constraint_exceptions"]["no_input_delay"]),7)
        self.assertEqual(len(result["reviewed_constraint_exceptions"]["no_output_delay"]),3)
        self.assertIn("not independent",result["constraint_policy"]["scope"])

    def test_different_platform_uuid_cannot_reuse_exceptions(self):
        result=self.evaluate(metadata=self.metadata.replace("b7ac1abe","00000000"))
        self.assertEqual(result["status"],"FAIL")
        self.assertIn("no_input_delay",result["unreviewed_constraints"])

    def test_changed_port_name_cannot_be_hidden_by_matching_count(self):
        result=self.evaluate(self.report.replace("io_uart_cmc_00_rxd","new_user_data_input"))
        self.assertEqual(result["status"],"FAIL")
        self.assertIn("no_input_delay",result["unreviewed_constraints"])

    def test_unknown_constraint_category_fails_closed(self):
        result=self.evaluate(self.report+"\n13. checking new_tool_check (0)\n-------------------------\n")
        self.assertEqual(result["status"],"FAIL")
        self.assertEqual(result["unknown_constraint_categories"],["new_tool_check"])

    def test_negative_hold_slack_cannot_pass_with_good_setup(self):
        path=self.directory/"metrics.json";data=json.loads(path.read_text());data["hold_whs_ns"]=-0.001
        path.write_text(json.dumps(data))
        self.assertEqual(self.evaluate()["status"],"FAIL")

    def test_targeted_negative_slack_cannot_be_hidden_by_global_summary(self):
        path=self.directory/"metrics.json";data=json.loads(path.read_text());data["targeted_pcie_setup_slack_ns"]=-1.607
        path.write_text(json.dumps(data))
        self.assertEqual(self.evaluate()["status"],"FAIL")

    def test_vendor_multicycle_contract_requires_exact_paths_and_positive_hold(self):
        path=self.directory/"targeted_pcie_timing.rpt";original=path.read_text()
        for changed in (original.replace("0.100ns","-0.001ns",1),
                        original.replace("Hold -start 3","Hold -start 1"),
                        original.replace("CORECLK","OTHERCLK"),
                        original[:original.rfind("Slack")]):
            path.write_text(changed)
            self.assertEqual(self.evaluate()["status"],"FAIL")

    def test_changed_vivado_patch_cannot_reuse_platform_exceptions(self):
        path=self.directory/"metrics.json";data=json.loads(path.read_text());data["tool"]["vivado_sw_build"]="changed"
        path.write_text(json.dumps(data))
        self.assertEqual(self.evaluate()["status"],"FAIL")

    def test_routed_clock_must_match_requested_frequency(self):
        (self.directory/"clocks.rpt").write_text("clk_kernel_00_unbuffered_net 3.333 {0.000 1.667}\n")
        self.assertEqual(self.evaluate()["status"],"FAIL")

    def test_runtime_clock_contract_requires_matching_default_target_and_metadata(self):
        for changed in (self.metadata.replace("Frequency: 150","Frequency: 300"),
                        self.metadata.replace("Default Freq: 300","Default Freq: 150"),
                        self.metadata.replace("Achieved Freq: 150","Achieved Freq: 149"),
                        self.metadata.replace("DATA_CLK","KERNEL_CLK")):
            self.assertEqual(self.evaluate(metadata=changed)["status"],"FAIL")
        self.assertEqual(builder.runtime_clock_contract_status(self.metadata,{})["status"],"FAIL")

    def test_partition_control_cannot_target_outer_wrapper_or_disappear(self):
        path=self.directory/"irq_structure.json";data=json.loads(path.read_text())
        data["kernel_partition_control"]["name"]="level0_i/ulp/mmul_sysbase_1"
        path.write_text(json.dumps(data));self.assertEqual(self.evaluate()["status"],"FAIL")
        data["kernel_partition_control"]["name"]="level0_i/ulp/mmul_sysbase_1/inst"
        data["kernel_partition_control"]["dont_partition"]=0
        path.write_text(json.dumps(data));self.assertEqual(self.evaluate()["status"],"FAIL")

    def test_irq_requires_positive_evidence_even_without_cdc_warnings(self):
        path=self.directory/"irq_structure.json";data=json.loads(path.read_text())
        data.pop("registered_source")
        path.write_text(json.dumps(data));result=self.evaluate()
        self.assertEqual(result["status"],"FAIL")
        self.assertEqual(result["irq_boundary"]["status"],"FAIL")

    def test_irq_gate_rejects_combinational_or_disconnected_source(self):
        changes=[lambda d:d["registered_source"]["source_pins"].append("extra/Q"),
                 lambda d:d["registered_source"].update(output_on_source_net=0),
                 lambda d:d["registered_source"].update(timing_startpoints=["different/C"]),
                 lambda d:d["cells"][0]["properties"].update(REF_NAME="LUT2"),
                 lambda d:d["connections"][0].update(fanin_pins=["extra/Q"]),
                 lambda d:d["connections"][1].update(destination_on_source_net=0),
                 lambda d:d["connections"][0].update(exception_selector_intersection=[]),
                 lambda d:d["destination_stages"].reverse(),
                 lambda d:d["connections"].pop()]
        for change in changes:
            data=irq_fixture();change(data)
            self.assertEqual(builder.irq_boundary_status(data)["status"],"FAIL")

    def test_irq_gate_requires_clock_attributes_and_both_interstage_timings(self):
        self.assertEqual(builder.irq_boundary_status(irq_fixture())["status"],"PASS")
        changes=[lambda d:d["cells"][0].update(clocks="dma_ip_axi_aclk_1"),
                 lambda d:d["cells"][1].update(clocks="other_clock"),
                 lambda d:d["cells"][2]["properties"].update(ASYNC_REG="FALSE"),
                 lambda d:d["cells"][3]["properties"].pop("ASYNC_REG"),
                 lambda d:d["connections"][1]["timing"]["setup"].update(count=0),
                 lambda d:d["connections"][2]["timing"]["hold"].update(slack_ns=None),
                 lambda d:d["connections"][1]["timing"]["setup"]["properties"].update(STARTPOINT_PIN="other/C"),
                 lambda d:d["connections"][2]["timing"]["hold"].update(slack_ns=-0.001),
                 lambda d:d["connections"][2]["timing"]["hold"].update(slack_ns=float("nan")),
                 lambda d:d["connections"][2]["timing"]["setup"]["properties"].update(EXCEPTION="False Path")]
        for change in changes:
            data=irq_fixture();change(data)
            self.assertEqual(builder.irq_boundary_status(data)["status"],"FAIL")

    def test_irq_input_cut_requires_authentic_contract_and_explicit_native_exception(self):
        data=irq_fixture()
        self.assertEqual(builder.irq_boundary_status(data,{})["status"],"FAIL")
        contract=json.loads((builder.HERE/"constraint_policy.json").read_text())["irq_input_cut"]
        contract["constraint"]=contract["constraint"].replace("intr_ff*[0]","intr_ff*[1]")
        self.assertEqual(builder.irq_boundary_status(data,contract)["status"],"FAIL")
        for kind in ("setup","hold"):
            data=irq_fixture();data["connections"][1]["timing"][kind]["properties"]["EXCEPTION"]=""
            self.assertEqual(builder.irq_boundary_status(data)["status"],"FAIL")
            data=irq_fixture();data["connections"][1]["timing"][kind]["slack_ns"]=0.0
            self.assertEqual(builder.irq_boundary_status(data)["status"],"FAIL")

    def test_routing_error_cannot_pass_with_good_timing(self):
        (self.directory/"route_status.rpt").write_text("# of nets with routing errors.......... : 1 :\n")
        self.assertEqual(self.evaluate()["status"],"FAIL")

    def test_bus_skew_violation_and_missing_paths_fail_closed(self):
        for report in ("Slack (VIOLATED) : -0.001ns\n","No parsed paths\n"):
            (self.directory/"bus_skew.rpt").write_text(report)
            self.assertEqual(self.evaluate()["status"],"FAIL")

    def test_unreviewed_cdc_and_methodology_findings_block_release(self):
        for kind,severity in (("cdc","Critical"),("cdc","Warning"),("methodology","Critical Warning"),("methodology","Warning")):
            (self.directory/"violations.json").write_text(json.dumps([
                {"kind":kind,"properties":{"NAME":"unreviewed finding","SEVERITY":severity}}]))
            result=self.evaluate()
            self.assertEqual(result["status"],"FAIL")
            self.assertEqual(len(result["unreviewed_findings"]),1)

    def test_lowered_drc_error_cannot_hide_behind_effective_warning(self):
        (self.directory/"violations.json").write_text(json.dumps([{"kind":"drc","properties":
            {"NAME":"HDPR-5#1","SEVERITY":"Warning","DEFAULT_RULE_SEVERITY":"Error"}}]))
        self.assertEqual(self.evaluate()["status"],"FAIL")
        (self.directory/"violations.json").write_text("[]\n")
        path=self.directory/"metrics.json";data=json.loads(path.read_text());data["drc_waivers_ignored"]=False
        path.write_text(json.dumps(data))
        self.assertEqual(self.evaluate()["status"],"FAIL")


class BuildCacheTests(unittest.TestCase):
    def test_implementation_preflight_must_execute_before_optimization_without_tool_errors(self):
        with tempfile.TemporaryDirectory(dir=HERE/"results") as directory:
            output=Path(directory);log=output/"_x/link/vivado/vpl/prj/prj.runs/impl_1/runme.log"
            log.parent.mkdir(parents=True)
            lines=["SYSBASE_CLOCK_API_COMPAT_INSTALLED","SYSBASE_CLOCK_SOLVER_PASS input_mhz=100 output_mhz=150",
                   "SYSBASE_IMPLEMENTATION_CLOCK_PASS period_ns=6.667","SYSBASE_KERNEL_DONT_PARTITION_PASS",
                   "Command: opt_design"]
            log.write_text("\n".join(lines)+"\n")
            self.assertEqual(builder.verify_implementation_frontend(output)["status"],"PASS")
            log.write_text("\n".join(lines)+"\nERROR: [Ip 78-110] Invalid part string Project\n")
            with self.assertRaisesRegex(RuntimeError,"logged errors"):
                builder.verify_implementation_frontend(output)
            log.write_text("Command: opt_design\n"+"\n".join(lines[:-1])+"\n")
            with self.assertRaisesRegex(RuntimeError,"before optimization"):
                builder.verify_implementation_frontend(output)

    def test_unknown_critical_warnings_and_incomplete_constraint_load_fail_closed(self):
        output=HERE/"results/synthetic_warning_test"
        with self.assertRaisesRegex(RuntimeError,"Unreviewed native critical"):
            builder.review_native_critical_warnings("CRITICAL WARNING: [Timing 99-999] Missing constraint\n",output)
        with self.assertRaisesRegex(RuntimeError,"Unreviewed native critical"):
            builder.review_native_critical_warnings("CRITICAL WARNING: [Common 17-55] 'set_property' expects at least one object. [different.xdc:1]\n",output)
        with self.assertRaisesRegex(RuntimeError,"Unmatched native"):
            builder.review_native_critical_warnings("Parsing XDC File [/tmp/clock.xdc] for cell 'clock'\n",output)

    def test_xo_with_external_include_dependency_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            output=Path(directory)
            component='''<component xmlns="http://www.spiritconsortium.org/XMLSchema/SPIRIT/1685-2009">
<fileSets><fileSet><name>synthesis</name><dependency>/original/source/tree</dependency></fileSet></fileSets></component>'''
            with zipfile.ZipFile(output/"mmul_sysbase.xo","w") as archive:
                archive.writestr("ip_repo/kernel/component.xml",component)
            with self.assertRaisesRegex(RuntimeError,"external or missing"):
                builder.unpack_xo(output)

    def test_completed_artifact_cannot_be_rehashed_on_resume(self):
        with tempfile.TemporaryDirectory() as directory:
            output=Path(directory);artifact=output/"mmul_sysbase.xclbin"
            artifact.write_bytes(b"original routed artifact")
            state={"completed":["snapshot","link"],"phase_artifacts":{"link":{"mmul_sysbase.xclbin":builder.sha(artifact)}}}
            builder.verify_phase_artifacts(state,output)
            artifact.write_bytes(b"another artifact with same kernel name")
            with self.assertRaisesRegex(RuntimeError,"artifact changed"):
                builder.verify_phase_artifacts(state,output)

    def test_generic_legacy_resume_has_no_automatic_hash_adoption(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(RuntimeError,"lacks historical output hashes"):
                builder.verify_phase_artifacts({"completed":["host_build"]},Path(directory))


class HardwareLaunchGateTests(unittest.TestCase):
    def test_both_loaded_user_and_management_modules_match_reviewed_contract(self):
        identity={"xrt_version":"reviewed", "xrt_commit":"commit",
                  "xocl_version":"user-version", "xocl_srcversion":"user-source",
                  "xclmgmt_version":"management-version", "xclmgmt_srcversion":"management-source"}
        contents={"/opt/xilinx/xrt/version.json":json.dumps({"BUILD_VERSION":"reviewed","VERSION_HASH":"commit"})}
        for module in ("xocl","xclmgmt"):
            for field in ("version","srcversion"):
                contents[f"/sys/module/{module}/{field}"]=identity[f"{module}_{field}"]
        with patch.object(Path,"read_text",lambda path:contents[str(path)]):
            self.assertEqual(gate.runtime_clock_driver_check({"runtime_identity":identity})["status"],"PASS")
            for module in ("xocl","xclmgmt"):
                for field in ("version","srcversion"):
                    key=f"/sys/module/{module}/{field}";original=contents[key]
                    contents[key]="different-loaded-module"
                    self.assertEqual(gate.runtime_clock_driver_check({"runtime_identity":identity})["status"],"FAIL")
                    contents[key]=original

    def setUp(self):
        self.args=SimpleNamespace(device="0000:04:00.1",xclbin=Path("verified.xclbin"),allow_program=True,timeout=10)
        self.artifact={"uuid":"selected","clock_topology":{"m_count":"1","m_clock_freq":[
            {"m_name":"DATA_CLK","m_type":"DATA","m_freq_Mhz":"150"}]}}
        self.before={"status":"PASS","loaded_xclbin_uuids":["prior"],
            "compute_units":[{"status":{"bits_set":["IDLE"]}}],"clocks":[{"id":"DATA_CLK","freq_mhz":"300"}]}
        self.after=json.loads(json.dumps(self.before));self.after["loaded_xclbin_uuids"]=["selected"]
        self.after["clocks"][0]["freq_mhz"]="150"
        self.result={"checks":{},"hardware_programming_attempted":False,"hardware_execution_attempted":False,"hardware_executed":False}

    def execute(self,program_result=None,board=None,program_exception=None,driver_status="PASS"):
        with patch.object(gate,"verify_device_mapping"),patch.object(gate,"runtime_clock_driver_check",return_value={"status":driver_status}),\
             patch.object(gate,"run_command",return_value=program_result or {"returncode":0},side_effect=program_exception) as program,\
             patch.object(gate,"inspect_board",return_value=board or self.after) as inspect,\
             patch.object(gate,"hardware_cases",return_value={"status":"PASS","cases":[]}) as host:
            try:gate.execute_checked_cases(self.args,Path("unused"),self.artifact,self.before,8,self.result,{})
            except BaseException:
                self.assertFalse(host.called,"Checked host launched before programming/identity/clock gates passed")
                raise
            return program,inspect,host

    def test_explicit_program_and_prelaunch_clock_check_precede_host(self):
        program,inspect,host=self.execute()
        self.assertEqual(program.call_args.args[0],[str(gate.XRT_SMI),"--batch","program","--device",self.args.device,"--user",str(self.args.xclbin)])
        self.assertTrue(inspect.called and host.called)
        self.assertEqual(self.result["checks"]["clock_pre_launch"]["status"],"PASS")
        self.assertTrue(self.result["hardware_executed"])

    def test_program_failure_never_launches_host(self):
        with self.assertRaisesRegex(gate.GateFailure,"programming"):
            self.execute(program_result={"returncode":1})
        self.assertTrue(self.result["hardware_programming_attempted"])
        self.assertTrue(self.result["device_may_have_changed"])
        self.assertFalse(self.result["hardware_executed"])
        with self.assertRaisesRegex(gate.GateFailure,"programming"):
            self.execute(program_result={"returncode":0,"timed_out":True})

    def test_bad_postprogram_uuid_clock_health_or_idle_prevents_host(self):
        for update in (lambda b:b.update(loaded_xclbin_uuids=["wrong"]),
                       lambda b:b["clocks"][0].update(freq_mhz="300"),
                       lambda b:b.update(status="FAIL"),
                       lambda b:b["compute_units"][0]["status"].update(bits_set=["START"]),
                       lambda b:b.update(compute_units=[])):
            board=json.loads(json.dumps(self.after));update(board)
            with self.assertRaises(gate.GateFailure):self.execute(board=board)

    def test_existing_uuid_still_requires_primary_clock_before_host(self):
        self.before["loaded_xclbin_uuids"]=["selected"]
        with self.assertRaisesRegex(gate.GateFailure,"Primary clock"):
            self.execute()
        self.assertFalse(self.result["hardware_programming_attempted"])

    def test_driver_identity_mismatch_and_missing_program_authorization_prevent_host(self):
        with self.assertRaisesRegex(gate.GateFailure,"Runtime XRT"):
            self.execute(driver_status="FAIL")
        self.args.allow_program=False
        with self.assertRaisesRegex(gate.GateFailure,"allow-program"):
            self.execute()
        self.assertFalse(self.result["hardware_programming_attempted"])


class CancellationTests(unittest.TestCase):
    def test_interrupted_program_records_uncertain_board_without_host_launch(self):
        for number in (signal.SIGINT,signal.SIGTERM):
            with self.subTest(signal=number),tempfile.TemporaryDirectory() as directory:
                root=Path(directory);output=root/"run";pid_path=root/"program_pid"
                artifact=root/"selected.xclbin";artifact.write_bytes(b"mock artifact")
                child="import os,time;from pathlib import Path;Path("+repr(str(pid_path))+").write_text(str(os.getpid()));time.sleep(120)"
                script="""import importlib.util,sys
from pathlib import Path
spec=importlib.util.spec_from_file_location('gate',sys.argv[1]);g=importlib.util.module_from_spec(spec);spec.loader.exec_module(g)
destination=Path(sys.argv[2]);artifact=Path(sys.argv[3]);child=sys.argv[4]
g.ROOT=destination.parent;fake=g.ROOT/'mock_runner.py';fake.write_text('# mocked runner identity');g.__file__=str(fake)
g.source_inventory=lambda: {};g.verify_device_mapping=lambda device: None
g.runtime_clock_driver_check=lambda contract: {'status':'PASS'}
g.inspect_board=lambda *args: {'status':'PASS','loaded_xclbin_uuids':['prior'],'compute_units':[{'status':{'bits_set':['IDLE']}}]}
g.inspect_xclbin=lambda *args: {'uuid':'selected'}
g.verify_provenance=lambda *args: {'status':'PASS','parameters':{'MAX_DIM':8},'record_data':{'build':{'implementation':{'runtime_clock_contract':{}}}}}
def forbidden_host(*args): raise AssertionError('Host must not launch during interrupted programming')
g.hardware_cases=forbidden_host
original=g.run_command
def mocked_program(command,output,stem,timeout=30):
    assert stem=='board_program'
    return original([sys.executable,'-c',child],output,stem,timeout)
g.run_command=mocked_program
sys.argv=['run.py','--output-dir',str(destination),'--xclbin',str(artifact),'--provenance',str(g.ROOT/'fake.json'),'--execute-hardware','--allow-program']
raise SystemExit(g.main())
"""
                process=subprocess.Popen([sys.executable,"-c",script,str(HERE/"run.py"),str(output),str(artifact),child],
                                         stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
                deadline=time.monotonic()+10
                while not pid_path.exists() and time.monotonic()<deadline:time.sleep(0.02)
                self.assertTrue(pid_path.exists(),"Mock program process failed to start")
                child_pid=int(pid_path.read_text());process.send_signal(number)
                stdout,stderr=process.communicate(timeout=10)
                self.assertEqual(process.returncode,128+number,(stdout,stderr))
                result=json.loads((output/"result.json").read_text())
                self.assertEqual(result["status"],"INCOMPLETE")
                self.assertTrue(result["hardware_programming_attempted"] and result["device_may_have_changed"])
                self.assertTrue(result["board_recheck_required"])
                self.assertFalse(result["hardware_executed"])
                with self.assertRaises(ProcessLookupError):os.kill(child_pid,0)

    def test_build_signal_records_incomplete_and_reaps_tool(self):
        for number in (signal.SIGINT,signal.SIGTERM):
            with self.subTest(signal=number),tempfile.TemporaryDirectory() as directory:
                root=Path(directory);output=root/"build";output.mkdir();pid_path=root/"child_pid"
                (output/"build_state.json").write_text(json.dumps({"status":"RUNNING","completed":["snapshot"],"inputs":[],"commands":[]}))
                child="import os,time;from pathlib import Path;Path("+repr(str(pid_path))+").write_text(str(os.getpid()));time.sleep(120)"
                script="""import importlib.util,sys
from pathlib import Path
spec=importlib.util.spec_from_file_location('builder',sys.argv[1]);b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
destination=Path(sys.argv[2]);child=sys.argv[3];b.ROOT=destination.parent
b.capture_toolchain=lambda: b.run([sys.executable,'-c',child],destination,'mock_tool',120)
sys.argv=['build.py','--output-dir',str(destination),'--resume']
raise SystemExit(b.main())
"""
                process=subprocess.Popen([sys.executable,"-c",script,str(HERE/"kernel/build.py"),str(output),child],
                                         stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
                deadline=time.monotonic()+10
                while not pid_path.exists() and time.monotonic()<deadline:time.sleep(0.02)
                self.assertTrue(pid_path.exists(),"Mock build tool failed to start")
                child_pid=int(pid_path.read_text());process.send_signal(number)
                stdout,stderr=process.communicate(timeout=10)
                self.assertEqual(process.returncode,128+number,(stdout,stderr))
                state=json.loads((output/"build_state.json").read_text())
                self.assertEqual(state["status"],"INCOMPLETE")
                self.assertEqual(state["signal"],number)
                with self.assertRaises(ProcessLookupError):os.kill(child_pid,0)

    def test_standalone_signal_records_incomplete_and_reaps_tool(self):
        for number in (signal.SIGINT,signal.SIGTERM):
            with self.subTest(signal=number),tempfile.TemporaryDirectory() as directory:
                root=Path(directory);output=root/"run";pid_path=root/"child_pid"
                child="import os,time;from pathlib import Path;Path("+repr(str(pid_path))+").write_text(str(os.getpid()));time.sleep(120)"
                script="""import importlib.util,sys
from pathlib import Path
spec=importlib.util.spec_from_file_location('gate',sys.argv[1]);gate=importlib.util.module_from_spec(spec);spec.loader.exec_module(gate)
gate.source_inventory=lambda: {}
def mock_read_only_tool(output,bdf,stem):
    gate.run_command([sys.executable,'-c',sys.argv[3]],output,stem,120)
    return {'status':'PASS'}
gate.inspect_board=mock_read_only_tool
destination=sys.argv[2]
sys.argv=['run.py','--output-dir',destination]
raise SystemExit(gate.main())
"""
                # Keep the child command in the closure before main replaces argv.
                script=script.replace("gate.source_inventory=lambda: {}","gate.source_inventory=lambda: {}\nchild_command=sys.argv[3]").replace("sys.argv[3]],output","child_command],output")
                process=subprocess.Popen([sys.executable,"-c",script,str(HERE/"run.py"),str(output),child],
                                         stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
                deadline=time.monotonic()+10
                while not pid_path.exists() and time.monotonic()<deadline:time.sleep(0.02)
                self.assertTrue(pid_path.exists(),"Mock tool failed to start")
                child_pid=int(pid_path.read_text())
                process.send_signal(number)
                stdout,stderr=process.communicate(timeout=10)
                self.assertEqual(process.returncode,128+number,(stdout,stderr))
                result=json.loads((output/"result.json").read_text())
                self.assertEqual(result["status"],"INCOMPLETE")
                self.assertFalse(result["hardware_execution_attempted"])
                self.assertEqual(result["signal"],number)
                with self.assertRaises(ProcessLookupError):os.kill(child_pid,0)


if __name__=="__main__":unittest.main()
