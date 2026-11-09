#!/usr/bin/env python3
"""Snapshot, test, package and link the genuine SysBase RTL; never program a board."""
import argparse
from collections import Counter
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import time
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
PLATFORM = "xilinx_u55c_gen3x16_xdma_3_202210_1"
STOP_SIGNAL = 0


class BuildInterrupted(Exception):
    def __init__(self, number):
        self.number=number
        super().__init__("Build interrupted by signal "+str(number))


def install_signal_handlers():
    def interrupted(number,_frame):
        global STOP_SIGNAL
        STOP_SIGNAL=number
    signal.signal(signal.SIGINT,interrupted)
    signal.signal(signal.SIGTERM,interrupted)


def stop_process_group(process):
    try:os.killpg(process.pid,signal.SIGTERM)
    except ProcessLookupError:pass
    try:process.wait(timeout=1)
    except subprocess.TimeoutExpired:pass
    try:os.killpg(process.pid,signal.SIGKILL)
    except ProcessLookupError:pass
    process.wait()


def sha(path):
    h=hashlib.sha256()
    with Path(path).open("rb") as f:
        for block in iter(lambda:f.read(1048576),b""):h.update(block)
    return h.hexdigest()


def run(command, output, label, timeout=600):
    if STOP_SIGNAL:raise BuildInterrupted(STOP_SIGNAL)
    log=output/(label+".log")
    environment={"PATH":"/usr/bin:/bin","HOME":str(Path.home()),"LANG":"C.UTF-8",
                 "XILINX_LOCAL_USER_DATA":"no"}
    # Limit all descendant tools to eight available CPUs; tool job limits also apply.
    cpus=sorted(os.sched_getaffinity(0))[:8]
    argv=["/usr/bin/taskset","-c",",".join(map(str,cpus))]+command
    started=time.monotonic()
    with log.open("w") as f:
        f.write(json.dumps(argv)+"\n");f.flush()
        p=subprocess.Popen(argv,cwd=output,env=environment,stdout=f,stderr=subprocess.STDOUT,start_new_session=True)
        try:
            while True:
                if STOP_SIGNAL:raise BuildInterrupted(STOP_SIGNAL)
                remaining=timeout-(time.monotonic()-started)
                if remaining<=0:raise RuntimeError(label+" timed out; "+str(log))
                try:
                    code=p.wait(timeout=min(0.2,remaining))
                    if STOP_SIGNAL:raise BuildInterrupted(STOP_SIGNAL)
                    break
                except subprocess.TimeoutExpired:continue
        except BaseException:
            stop_process_group(p)
            raise
    result={"label":label,"command":argv,"returncode":code,"log":str(log),"seconds":round(time.monotonic()-started,3)}
    if code:raise RuntimeError(label+" failed; "+str(log))
    return result


def amd(tool, arguments):
    settings="/tools/Xilinx/2025.1/"+("Vivado" if tool=="vivado" else "Vitis")+"/settings64.sh"
    executable="/tools/Xilinx/2025.1/"+("Vivado" if tool=="vivado" else "Vitis")+"/bin/"+tool
    return ["/bin/bash","-c",'source "$1"; shift; exec "$@"',"amd-tool",settings,executable]+arguments


def capture_toolchain():
    paths=[Path("/opt/xilinx/xrt/version.json"),Path("/opt/xilinx/xrt/lib/libxrt_coreutil.so").resolve(),
           Path("/usr/bin/g++").resolve(),Path("/tools/Xilinx/2025.1/Vivado/bin/unwrapped/lnx64.o/vivado"),
           Path("/tools/Xilinx/2025.1/Vitis/bin/unwrapped/lnx64.o/v++")]
    headers=[{"path":str(path),"sha256":sha(path)} for path in sorted(Path("/opt/xilinx/xrt/include").rglob("*")) if path.is_file()]
    return {"scope":"Captured before compilation by the build coordinator",
            "captured_utc":time.strftime("%Y-%m-%dT%H:%M:%SZ",time.gmtime()),
            "xrt":json.loads(Path("/opt/xilinx/xrt/version.json").read_text()),
            "compiler_version":subprocess.check_output(["/usr/bin/g++","-dumpfullversion"],text=True).strip(),
            "executable_and_library_hashes":{str(path):sha(path) for path in paths},"xrt_header_files":headers}


def verify_toolchain(toolchain):
    for path,expected in toolchain["executable_and_library_hashes"].items():
        if sha(Path(path))!=expected:raise RuntimeError("Installed toolchain changed since build capture: "+path)
    for item in toolchain["xrt_header_files"]:
        if sha(Path(item["path"]))!=item["sha256"]:raise RuntimeError("XRT header changed since build capture: "+item["path"])


def tool_versions(state,output):
    versions={"xrt":state["toolchain"]["xrt"]["BUILD_VERSION"],"compiler":state["toolchain"]["compiler_version"]}
    for tool,log,label in (("Vivado","package.log","vivado"),("v++","link.log","vitis")):
        text=(output/log).read_text(errors="replace")
        version=re.search(r"\*+ "+re.escape(tool)+r" v(\S+)",text)
        build=re.search(r"SW Build (\S+) on ([^\n]+)",text)
        if not version or not build:raise RuntimeError("Missing actual tool banner in "+log)
        versions[label]={"version":version[1],"sw_build":build[1],"build_date":build[2].strip()}
    return versions


def verify_phase_artifacts(state, output):
    for phase in state["completed"]:
        if phase=="snapshot":continue
        records=state.get("phase_artifacts",{}).get(phase)
        if not records:
            raise RuntimeError("Completed phase lacks historical output hashes: "+phase+
                               "; rebuild or explicitly migrate an observed live build")
        for relative,expected in records.items():
            path=(output/relative).resolve()
            if not path.is_relative_to(output) or not path.is_file() or sha(path)!=expected:
                raise RuntimeError("Completed phase artifact changed: "+phase+": "+relative)


def import_observed_migration(state,output,ledger_path,state_path):
    ledger=json.loads(ledger_path.read_text())
    if (ledger.get("kind")!="observed_live_build_migration" or ledger.get("status")!="COMPLETE" or
        ledger.get("build_directory")!=str(output) or ledger.get("source_inputs")!=state["inputs"] or
        ledger.get("final_build_state_sha256")!=sha(state_path)):
        raise RuntimeError("Migration is not the completed observation of this exact original build")
    if sha(ledger_path.parent/"observe.py")!=ledger.get("observer_sha256"):
        raise RuntimeError("Migration observer source changed")
    if state.get("phase_artifacts") or state.get("migration"):
        raise RuntimeError("An observed legacy build can be migrated only once")
    state["phase_artifacts"]={phase:entry["files"] for phase,entry in ledger["phase_artifacts"].items()}
    verify_phase_artifacts(state,output)
    toolchain_path=ledger_path.parent/"toolchain_observation.json"
    toolchain=json.loads(toolchain_path.read_text())
    if toolchain.get("original_pid")!=ledger["original_pid"] or toolchain.get("original_start_ticks")!=ledger["original_start_ticks"]:
        raise RuntimeError("Toolchain observation does not belong to the observed original coordinator")
    verify_toolchain(toolchain)
    state["toolchain"]=toolchain
    state["completed"].append("toolchain")
    state["phase_artifacts"]["toolchain"]={str(toolchain_path.relative_to(output)):sha(toolchain_path)}
    state["migration"]={"path":str(ledger_path.relative_to(ROOT)),"sha256":sha(ledger_path),
                        "observer_path":str((ledger_path.parent/"observe.py").relative_to(ROOT)),
                        "observer_sha256":ledger["observer_sha256"],"original_pid":ledger["original_pid"],
                        "observed_active_utc":ledger["observed_active_utc"]}


def phase_outputs(name,output):
    if name=="axi_test":return [output/"axi_sim/result.json"]+list((output/"axi_sim").glob("*.log"))
    if name=="host_build":return [output/"sysbase_checked_host",output/"host_build.log"]
    if name=="package":return [output/n for n in ("mmul_sysbase.xo","synthesis_hierarchy.txt","packaged_synth.dcp","packaged_utilization.rpt","package.log")]
    if name=="link":
        dcps=list(output.glob("_x/link/vivado/vpl/prj/prj.runs/impl_1/*_routed.dcp"))
        if len(dcps)!=1:raise RuntimeError("Expected one routed DCP when recording completed link outputs")
        vpl=output/"_x/link/vivado/vpl"
        generated=[vpl/name for name in ("scripts/_vpl_pre_place.tcl","scripts/_vpl_post_init.tcl",
            "scripts/impl_1/_full_init_pre.tcl","scripts/impl_1/_full_init_post.tcl",
            "output/_user_impl_clk.xdc","output/dont_partition.xdc","prj/prj.runs/impl_1/runme.log",
            ".local/hw_platform/hw_bb_locked.dcp")]
        return [output/"mmul_sysbase.xclbin",output/"link.log",output/"connectivity.cfg"]+dcps+generated
    if name=="platform_metadata":return [output/"platform_metadata.log"]
    if name=="package_qualification":
        dcps=list((output/"package_qualification").rglob("qualified_sysbase.dcp"))
        if len(dcps)!=1:raise RuntimeError("Expected one unpacked-package synthesis checkpoint")
        return [output/"package_qualification/qualification.txt",output/"package_qualification.log",
                output/"package_qualification/package_inputs.json"]+dcps
    raise RuntimeError("No output contract for phase "+name)


def packaged_parameters(xo):
    namespace={"s":"http://www.spiritconsortium.org/XMLSchema/SPIRIT/1685-2009"}
    with zipfile.ZipFile(xo) as archive:
        names=[name for name in archive.namelist() if name.startswith("ip_repo/") and name.endswith("/component.xml")]
        if len(names)!=1:raise RuntimeError("Expected one kernel component in XO")
        component=ET.fromstring(archive.read(names[0]))
    values={item.find("s:name",namespace).text:int(item.find("s:value",namespace).text)
        for item in component.findall(".//s:modelParameter",namespace)}
    expected={"C_S_AXI_CONTROL_ADDR_WIDTH":6,"C_S_AXI_CONTROL_DATA_WIDTH":32,
        "C_M_AXI_ADDR_WIDTH":64,"C_M_AXI_DATA_WIDTH":32,"C_M_AXI_ID_WIDTH":1,"C_M_AXI_USER_WIDTH":1,
        "MAX_DIM":8,"ARRAY_SIZE":4}
    if values!=expected:raise RuntimeError("Packaged kernel parameters differ from the supported pilot: "+str(values))
    return values


def unpack_xo(output):
    destination=output/"unpacked_xo"
    if destination.exists():shutil.rmtree(destination)
    with zipfile.ZipFile(output/"mmul_sysbase.xo") as archive:
        for member in archive.infolist():
            if not (destination/member.filename).resolve().is_relative_to(destination):
                raise RuntimeError("XO member escapes the unpacked package")
        archive.extractall(destination)
    components=list((destination/"ip_repo").glob("*/component.xml"))
    if len(components)!=1:raise RuntimeError("Expected one packaged kernel IP")
    component=components[0];namespace={"s":"http://www.spiritconsortium.org/XMLSchema/SPIRIT/1685-2009"}
    for group in ET.parse(component).findall(".//s:fileSet",namespace):
        include_roots=[]
        for entry in group.findall("s:file/s:name",namespace)+group.findall("s:dependency",namespace):
            value=entry.text or ""
            path=(component.parent/value).resolve()
            if Path(value).is_absolute() or not path.is_relative_to(component.parent) or not path.exists():
                raise RuntimeError("Packaged IP has an external or missing file/dependency: "+value)
            if path.is_dir():include_roots.append(path)
        for entry in group.findall("s:file/s:name",namespace):
            path=component.parent/entry.text
            if path.suffix not in (".v",".sv",".vh",".svh"):continue
            for include in re.findall(r'^\s*`include\s+"([^"]+)"',path.read_text(),re.M):
                candidates=[(base/include).resolve() for base in [path.parent]+include_roots]
                if not any(candidate.is_relative_to(component.parent) and candidate.is_file() for candidate in candidates):
                    raise RuntimeError("Packaged HDL include cannot resolve inside the XO: "+include)
    parameters=packaged_parameters(output/"mmul_sysbase.xo")
    records={str(path.relative_to(destination)):sha(path) for path in sorted(destination.rglob("*")) if path.is_file()}
    evidence=output/"package_qualification";evidence.mkdir(exist_ok=True)
    (evidence/"package_inputs.json").write_text(json.dumps({"xclbin_object_sha256":sha(output/"mmul_sysbase.xo"),
        "scope":"Unpacked XO files only; all IP metadata paths must remain inside the package",
        "parameters":parameters,"files":records},indent=2)+"\n")
    return destination


def targeted_pcie_contract(report):
    """Qualify the delivered CFGPHYLINKDOWN MCP, without modifying constraints."""
    source="level0_i/blp/blp_i/ss_hif/inst/pcie/inst/bd_39ab_pcie_0_pcie_4_0_pipe_inst/pcie_4_c_e4_inst/CORECLK"
    destination="level0_i/blp/blp_i/PLP/ss_dma/inst/dma/inst/chain_cfg_phy_link_down/with_ff_chain.ff_chain_gen[0].sync_rst.ff_chain_reg[1][0]/D"
    paths=[]
    for block in re.split(r"(?m)(?=^Slack\s*\()",report)[1:]:
        fields={name:re.search(pattern,block,re.M) for name,pattern in {
            "slack":r"^Slack\s*\((MET|VIOLATED)\)\s*:\s*([+-]?[0-9]+(?:\.[0-9]+)?)ns",
            "source":r"^\s*Source:\s*(\S+)","destination":r"^\s*Destination:\s*(\S+)",
            "type":r"^\s*Path Type:\s*(Setup|Hold)\b",
            "exception":r"^\s*Timing Exception:\s*MultiCycle Path\s+Setup -start 4(?:\s+Hold\s+-start 3)?\s*$"}.items()}
        if not all(fields.values()):return {"status":"FAIL","reason":"Missing exact targeted path fields"}
        slack=float(fields["slack"][2]);kind=fields["type"][1]
        if (fields["source"][1]!=source or fields["destination"][1]!=destination or
            fields["slack"][1]!="MET" or not math.isfinite(slack) or slack<0 or
            (kind=="Hold" and not re.search(r"Hold\s+-start 3",fields["exception"][0]))):
            return {"status":"FAIL","reason":"Targeted path identity, MCP contract, or slack changed"}
        paths.append({"type":kind,"slack_ns":slack})
    setup=[path["slack_ns"] for path in paths if path["type"]=="Setup"]
    hold=[path["slack_ns"] for path in paths if path["type"]=="Hold"]
    return {"status":"PASS" if setup and hold else "FAIL","setup_paths":len(setup),"hold_paths":len(hold),
        "setup_slack_ns":min(setup,default=None),"hold_slack_ns":min(hold,default=None),
        "source":source,"destination":destination,"setup_cycles_start":4,"hold_cycles_start":3,
        "scope":"Adoption of installed vendor PCIe CFGPHYLINKDOWN MCP; no constraints added or relaxed"}


def irq_boundary_status(evidence, contract=None):
    """Require a registered source, vendor ingress and marked two-stage sync."""
    policy=json.loads((HERE/"constraint_policy.json").read_text())
    if contract is None:contract=policy.get("irq_input_cut",{})
    stages=["level0_i/ii_level0_pipe/inst/pxi_ii_core/inst/ip_irq_cu_00/inst/q_i_reg[1]"]+[
        "level0_i/blp/blp_i/PLP/ss_ert/inst/user_peripherals/intc_hierarchy/axi_intc_cu_bank_00/U0/INTC_CORE_I/"
        f"INTR_DETECT_GEN[1].ASYNC_GEN.intr_ff_reg[{index}]" for index in (0,1)]
    reasons=[]
    expected_scope="level0_i/blp/blp_i/PLP/ss_ert/inst/user_peripherals/intc_hierarchy/axi_intc_cu_bank_00/U0"
    expected_cut="set_false_path -to [get_cells -filter IS_SEQUENTIAL {INTC_CORE_I/*ASYNC_GEN.intr_ff*[0]}]"
    cut_source=contract.get("source",{})
    source_file=(ROOT/cut_source.get("path","")).resolve()
    fragment=("current_instance "+expected_scope+"\nset_property src_info "
              "{type:SCOPED_XDC file:131 line:47 export:INPUT save:NONE read:READ} [current_design]\n"+expected_cut)
    contract_verified=(contract.get("static_dcp_sha256")==policy.get("static_dcp_sha256") and
        contract.get("scoped_instance")==expected_scope and contract.get("constraint")==expected_cut and
        contract.get("source_file_id")==131 and contract.get("source_line")==47 and
        source_file.is_relative_to(ROOT) and source_file.is_file() and sha(source_file)==cut_source.get("sha256") and
        fragment in source_file.read_text())
    if not contract_verified:reasons.append("Missing or changed authentic vendor first-stage input-cut contract")
    source=evidence.get("registered_source",{})
    pins=source.get("source_pins",[]);names=source.get("source_cells",[])
    source_name=names[0] if len(names)==1 else ""
    source_pin=pins[0] if len(pins)==1 else ""
    if (source.get("output_pin")!="level0_i/ulp/mmul_sysbase_1/inst/interrupt" or
        not source_name.startswith("level0_i/ulp/mmul_sysbase_1/inst/") or source_pin!=source_name+"/Q" or
        source.get("timing_startpoints")!=[source_name+"/C"] or source.get("output_on_source_net")!=1):
        reasons.append("Interrupt output lacks one direct registered launch point")
    records=evidence.get("cells",[])
    cells={cell.get("name"):cell for cell in records}
    if len(cells)!=len(records):reasons.append("Duplicate IRQ cell records")
    for index,name in enumerate([source_name]+stages):
        cell=cells.get(name,{})
        expected_clock="clk_kernel_00_unbuffered_net" if index==0 else "dma_ip_axi_aclk_1"
        if cell.get("clocks")!=expected_clock or cell.get("properties",{}).get("REF_NAME")!="FDRE":
            reasons.append("Missing FDRE or incorrect clock at "+name)
        if index>=2 and str(cell.get("properties",{}).get("ASYNC_REG","")).lower() not in ("true","1"):
            reasons.append("Destination synchronizer stage lacks ASYNC_REG: "+name)
    if evidence.get("destination_stages")!=stages:reasons.append("Destination chain identity changed")
    connections=evidence.get("connections",[])
    if len(connections)!=3:reasons.append("Incomplete interrupt connectivity evidence")
    previous=source_pin
    for index,(connection,stage) in enumerate(zip(connections,stages)):
        if (connection.get("from_pin")!=previous or connection.get("to_pin")!=stage+"/D" or
            connection.get("fanin_pins")!=[previous] or not connection.get("net_segments") or
            connection.get("fanin_startpoints")!=[previous.rsplit("/",1)[0]+"/C"] or
            connection.get("destination_on_source_net")!=1):
            reasons.append("Interrupt chain is disconnected or contains extra logic at "+stage)
        if index==0:
            selected=connection.get("exception_selector_intersection",[])
            # Hierarchical selector pins must lie on this actual source net.
            if not selected or any(not pin.startswith("level0_i/ulp/") or "lp_s_irq_cu_00" not in pin for pin in selected):
                reasons.append("Actual interrupt net does not intersect the inherited false-path selector")
        else:
            for kind in ("setup","hold"):
                timing=connection.get("timing",{}).get(kind,{})
                slack=timing.get("slack_ns")
                properties=timing.get("properties",{})
                if index==1:
                    if (timing.get("count")!=1 or slack is not None or properties.get("SLACK")!="" or
                        properties.get("EXCEPTION")!="False Path" or properties.get("LOGIC_LEVELS")!="0"):
                        reasons.append("Vendor ingress input cut is absent, changed, or falsely labeled timed")
                elif (timing.get("count")!=1 or isinstance(slack,bool) or not isinstance(slack,(int,float)) or
                      not math.isfinite(slack) or slack<0 or properties.get("EXCEPTION")!=""):
                    reasons.append("Missing, excepted, or failing marked synchronizer "+kind+" path at "+stage)
                if (properties.get("STARTPOINT_PIN")!=previous.rsplit("/",1)[0]+"/C" or
                    properties.get("ENDPOINT_PIN")!=stage+"/D" or properties.get("STARTPOINT_CLOCK")!="dma_ip_axi_aclk_1" or
                    properties.get("ENDPOINT_CLOCK")!="dma_ip_axi_aclk_1" or properties.get("DELAY_TYPE")!={"setup":"max","hold":"min"}[kind]):
                    reasons.append("Interstage timing path identity or clocks changed at "+stage)
        previous=stage+"/Q"
    return {"status":"FAIL" if reasons else "PASS","reasons":reasons,"source":source,
        "model":"registered_source_vendor_ingress_two_stage_sync_v1",
        "vendor_input_cut":{"verified":contract_verified,"contract":contract},
        "destination_stages":stages,"connections":connections,
        "scope":"Positive registered-source and vendor ingress connectivity; q_i to intr_ff0 intentionally untimed under authentic input cut; final ASYNC_REG pair requires passing unexcepted setup/hold. Exact CDC finding review remains separate."}


def runtime_clock_contract_status(metadata, policy):
    contract=dict(policy.get("runtime_clock_contract",{}))
    system=re.findall(r"Name:\s*ulp_ucs_aclk_kernel_00\s+Type:\s*SCALABLE\s+Default Freq:\s*([0-9.]+) MHz\s+Requested Freq:\s*([0-9.]+) MHz\s+Achieved Freq:\s*([0-9.]+) MHz",metadata)
    topology=re.findall(r"Name:\s*DATA_CLK\s+Index:\s*\d+\s+Type:\s*DATA\s+Frequency:\s*([0-9.]+) MHz",metadata)
    expected_identity={"xrt_version":"2.19.194","xrt_commit":"7d8151e6ee73c6ec2e99501a58c9c2eca6cc68ce",
        "xocl_version":"2.19.194,7d8151e6ee73c6ec2e99501a58c9c2eca6cc68ce","xocl_srcversion":"EDD70ECBCA2CFAECF0EA618",
        "xclmgmt_version":"2.19.194,7d8151e6ee73c6ec2e99501a58c9c2eca6cc68ce","xclmgmt_srcversion":"9294FC7BCBE71B416A4F793"}
    passed=(contract.get("model")=="xrt_scalable_primary_clock_v1" and contract.get("default_mhz")==300 and
        contract.get("requested_mhz")==150 and contract.get("runtime_identity")==expected_identity and
        contract.get("prelaunch_program_clock_gate_required") is True and
        len(system)==1 and tuple(map(float,system[0]))==(300,150,150) and len(topology)==1 and float(topology[0])==150)
    contract.update(status="PASS" if passed else "FAIL",system_clock_records=system,data_clock_records=topology)
    return contract


def signoff_status(directory, artifact_metadata, assessment_dir=None):
    assessment_dir=assessment_dir or directory
    assessment_dir.mkdir(parents=True,exist_ok=True)
    metrics=json.loads((directory/"metrics.json").read_text())
    check=(directory/"check_timing.rpt").read_text()
    counts={name:int(n) for name,n in re.findall(r"checking (\w+) \((\d+)\)",check)}
    required={"no_clock","constant_clock","pulse_width_clock","unconstrained_internal_endpoints","no_input_delay","no_output_delay",
              "multiple_clock","generated_clocks","loops","partial_input_delay","partial_output_delay","latch_loops"}
    metrics["constraint_counts"]=counts
    metrics["unreviewed_constraints"]={name:counts.get(name,"missing") for name in sorted(required) if counts.get(name)!=0}
    metrics["unknown_constraint_categories"]=sorted(set(counts)-required)
    policy_path=HERE/"constraint_policy.json"
    policy=json.loads(policy_path.read_text())
    metrics["runtime_clock_contract"]=runtime_clock_contract_status(artifact_metadata,policy)
    if policy.get("finding_signature")!="exact_properties_except_report_local_id_name_v1":
        raise RuntimeError("Unsupported finding signature policy")
    for evidence in policy.get("review_evidence",[]):
        path=(ROOT/evidence["path"]).resolve()
        if not path.is_relative_to(ROOT) or not path.is_file() or sha(path)!=evidence["sha256"]:
            raise RuntimeError("Vendor finding review evidence changed: "+evidence["path"])
    vbnv=re.search(r"Platform VBNV:\s*(\S+)",artifact_metadata)
    uuid=re.search(r"Static UUID:\s*([a-fA-F0-9-]+)",artifact_metadata)
    metrics["platform"]={"vbnv":vbnv[1] if vbnv else None,"interface_uuid":uuid[1].lower() if uuid else None}
    matching=(metrics["platform"]["vbnv"]==policy["platform_vbnv"] and
              metrics["platform"]["interface_uuid"]==policy["platform_interface_uuid"] and
              metrics.get("tool")==policy["tool"])
    metrics["reviewed_constraint_exceptions"]={}
    if matching:
        for category in ("no_input_delay","no_output_delay"):
            section=re.search(r"(?ms)^\d+\. checking "+category+r" \(\d+\)\n-+\n(.*?)(?=^\d+\. checking|\Z)",check)
            names=[] if not section else [line.strip() for line in section[1].splitlines()
                if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_\[\]./]*",line.strip())]
            if sorted(names)==sorted(policy[category]) and counts.get(category)==len(names):
                metrics["unreviewed_constraints"].pop(category,None)
                metrics["reviewed_constraint_exceptions"][category]=policy[category]
    captured_policy=assessment_dir/"constraint_policy.json"
    shutil.copy2(policy_path,captured_policy)
    metrics["constraint_policy"]={"path":str(captured_policy.relative_to(ROOT)),"sha256":sha(captured_policy),
                                  "scope":policy["scope"],"platform_identity_matched":matching}
    violations=json.loads((directory/"violations.json").read_text())
    metrics["unreviewed_findings"]=[]
    metrics["reviewed_findings"]=[]
    metrics["finding_signature"]=policy["finding_signature"]
    metrics["finding_counts"]={"drc":0,"cdc":0,"methodology":0}
    metrics["drc_check_settings"]=json.loads((directory/"drc_checks.json").read_text())
    metrics["drc_check_overrides"]=[entry for entry in metrics["drc_check_settings"]
        if entry["effective_severity"]!=entry["default_severity"] or entry["effective_enabled"]!=entry["default_enabled"]]
    hdpr=[entry for entry in metrics["drc_check_settings"] if entry["name"]=="HDPR-5"]
    metrics["drc_factory_check_verified"]=(len(hdpr)==1 and hdpr[0]["default_severity"]=="Error" and hdpr[0]["default_enabled"]==1)
    for finding in violations:
        kind=finding.get("kind")
        properties=finding.get("properties",{})
        severity=properties.get("SEVERITY","").strip()
        signature=finding_signature(finding)
        metrics["finding_counts"][kind]=metrics["finding_counts"].get(kind,0)+1
        gated=(kind not in ("drc","cdc","methodology") or severity not in ("Info","Advisory","Warning","Critical","Critical Warning","Error")
               or severity in ("Error","Critical","Critical Warning") or (kind!="drc" and severity=="Warning")
               or (kind=="drc" and properties.get("DEFAULT_RULE_SEVERITY") in ("Error","Critical","Critical Warning")))
        if gated:
            exception=policy.get("finding_exceptions",{}).get(signature)
            detail={"signature":signature,"kind":kind,"severity":severity,"properties":properties}
            review_class=exception.get("review_class") if exception else None
            reason=exception.get("reason") if exception else None
            if review_class:reason=policy.get("review_classes",{}).get(review_class,{}).get("reason")
            if matching and exception and reason:
                metrics["reviewed_findings"].append(dict(detail,reason=reason,review_class=review_class))
            else:metrics["unreviewed_findings"].append(detail)
    timing=(directory/"timing_summary.rpt").read_text()
    metrics["all_user_timing_constraints_met"]="All user specified timing constraints are met" in timing
    route=(directory/"route_status.rpt").read_text()
    match=re.search(r"# of nets with routing errors[.\s]*:\s*(\d+)",route,re.I)
    metrics["routing_errors"]=int(match[1]) if match else None
    skew=(directory/"bus_skew.rpt").read_text()
    paths=re.findall(r"Slack\s*\((MET|VIOLATED)\)\s*:\s*([+-]?[0-9]+(?:\.[0-9]+)?)ns",skew)
    metrics["bus_skew"]={"reported_constraints":len(paths),
        "minimum_slack_ns":min((float(value) for _,value in paths),default=None),
        "status":"PASS" if paths and all(state=="MET" and float(value)>=0 for state,value in paths)
            and "VIOLATED" not in skew else "FAIL"}
    metrics["targeted_pcie_contract"]=targeted_pcie_contract((directory/"targeted_pcie_timing.rpt").read_text())
    irq_evidence=json.loads((directory/"irq_structure.json").read_text())
    metrics["irq_boundary"]=irq_boundary_status(irq_evidence)
    metrics["kernel_partition_control"]=irq_evidence.get("kernel_partition_control",{})
    partition=metrics["kernel_partition_control"]
    partition["status"]="PASS" if (partition.get("count")==1 and partition.get("dont_partition")==1 and
        partition.get("name")=="level0_i/ulp/mmul_sysbase_1/inst" and partition.get("orig_ref_name")=="mmul_sysbase" and
        partition.get("ref_name")=="ulp_mmul_sysbase_1_0_mmul_sysbase") else "FAIL"
    clock=re.findall(r"(?m)^clk_kernel_00_unbuffered_net\s+([0-9]+(?:\.[0-9]+)?)\s+\{",(directory/"clocks.rpt").read_text())
    period=float(clock[0]) if len(clock)==1 else None
    metrics["kernel_clock"]={"name":"clk_kernel_00_unbuffered_net","period_ns":period,"requested_mhz":150,
        "status":"PASS" if period is not None and abs(period-1000/150)<=0.001 else "FAIL"}
    metrics["status"]="PASS" if (metrics["setup_wns_ns"]>=0 and metrics["hold_whs_ns"]>=0 and
        metrics["drc_errors"]==0 and metrics["drc_critical_warnings"]==0 and not metrics["unreviewed_constraints"] and
        metrics.get("drc_default_settings_applied") is True and metrics.get("drc_waivers_ignored") is True and
        metrics["drc_factory_check_verified"] and
        metrics["all_user_timing_constraints_met"] and metrics["routing_errors"]==0 and
        metrics["bus_skew"]["status"]=="PASS" and
        metrics["targeted_pcie_contract"]["status"]=="PASS" and
        metrics["kernel_clock"]["status"]=="PASS" and
        metrics["kernel_partition_control"]["status"]=="PASS" and
        metrics["irq_boundary"]["status"]=="PASS" and
        metrics["runtime_clock_contract"]["status"]=="PASS" and
        metrics.get("targeted_pcie_setup_paths")==1 and metrics.get("targeted_pcie_setup_slack_ns",-1)>=0 and
        not metrics["unknown_constraint_categories"] and not metrics["unreviewed_findings"]) else "FAIL"
    (assessment_dir/"result.json").write_text(json.dumps(metrics,indent=2)+"\n")
    return metrics


def finding_signature(finding):
    # Vivado renumbers records between reports; all actual finding properties
    # remain exact. Full unnormalized objects are retained in violations.json.
    semantic={"kind":finding["kind"],"properties":{key:value for key,value in finding["properties"].items()
        if key not in ("ID","NAME")}}
    return hashlib.sha256(json.dumps(semantic,sort_keys=True,separators=(",",":")).encode()).hexdigest()


def verify_vendor_platform(output):
    policy=json.loads((HERE/"constraint_policy.json").read_text())
    expected=policy.get("static_dcp_sha256")
    path=output/"_x/link/vivado/vpl/.local/hw_platform/hw_bb_locked.dcp"
    if not expected or not path.is_file() or sha(path)!=expected:
        raise RuntimeError("Current build static DCP differs from the reviewed delivered vendor platform")
    return {"status":"PASS","path":str(path.relative_to(ROOT)),"sha256":expected,
        "scope":"Byte-identical reviewed installed vendor static platform; inherited assumptions retained"}


def verify_implementation_frontend(output):
    path=output/"_x/link/vivado/vpl/prj/prj.runs/impl_1/runme.log"
    log=path.read_text(errors="replace")
    errors=re.findall(r"(?m)^ERROR:.*$",log)
    if errors:raise RuntimeError("Implementation tool logged errors: "+"; ".join(errors[:5]))
    optimization=log.find("Command: opt_design")
    markers=("SYSBASE_CLOCK_API_COMPAT_INSTALLED","SYSBASE_CLOCK_SOLVER_PASS",
             "SYSBASE_IMPLEMENTATION_CLOCK_PASS","SYSBASE_KERNEL_DONT_PARTITION_PASS")
    for marker in markers:
        match=re.search(r"(?m)^"+marker+r"[^\n]*$",log)
        if not match or optimization<0 or match.start()>optimization:
            raise RuntimeError("Required implementation preflight did not execute before optimization: "+marker)
    warnings=review_native_critical_warnings(log,output)
    return {"status":"PASS","log_path":str(path.relative_to(ROOT)),"log_sha256":sha(path),
            "tool_errors":0,"required_before_optimization":list(markers),"critical_warning_review":warnings}


def review_native_critical_warnings(log,output):
    """Only exact, separately qualified generated-flow cases are acceptable."""
    vpl=output/"_x/link/vivado/vpl"
    expected={
        "Project 1-840":f"The design checkpoint file '{vpl}/prj/prj.runs/my_rm_synth_1/ulp.dcp' was generated for an IP by an out of context synthesis run and should not be used directly as a source in a Vivado flow. Constraints and other files related to the IP are only stored in the xci/xcix, not the checkpoint. It is strongly recommended that the original IP source file (.xci/.xcix) be used.",
        "Common 17-55":f"'set_property' expects at least one object. [{vpl}/output/dont_partition.xdc:1]",
        "Vivado 12-4430":"You are lowering the severity from an ERROR. This can potentially lead to board damage or other functionality issues on hardware. If this is not desired, please run 'reset_property SEVERITY [get_drc_checks HDPR-5]' to undo this change."}
    reasons={"Project 1-840":"Generated DFX RM stitching; original BD/IP companion constraints must be loaded with matched native parse records. Actual clock, unconstrained-path and factory-DRC gates remain required.",
        "Common 17-55":"Exact generated SDX_KERNEL selector loses OOC metadata; owned pre-optimization hook restores the qualified inner instance, with final routed property verification.",
        "Vivado 12-4430":"Generated HDPR-5 downgrade is retained as evidence; final unwaived factory-severity DRC must have no actual Error/Critical violations."}
    records=[]
    for line in re.findall(r"(?m)^CRITICAL WARNING:.*$",log):
        match=re.fullmatch(r"CRITICAL WARNING: \[([^\]]+)\] (.*)",line)
        if not match or expected.get(match[1])!=match[2]:
            raise RuntimeError("Unreviewed native critical warning: "+line)
        records.append({"id":match[1],"message":match[2],"disposition":reasons[match[1]]})
    starts=re.findall(r"(?m)^Parsing XDC File \[([^\]]+)\](.*)$",log)
    finishes=re.findall(r"(?m)^Finished Parsing XDC File \[([^\]]+)\](.*)$",log)
    if Counter(starts)!=Counter(finishes):raise RuntimeError("Unmatched native companion-XDC parse records")
    companions=[{"path":path,"scope":scope.strip()} for path,scope in sorted(set(starts))]
    if any(record["id"]=="Project 1-840" for record in records):
        roles={"hbm":lambda p,s:p.endswith("/hbm_ip.xdc") and "level0_i/ulp/hmss_0/inst/hbm_inst/inst" in s,
            "primary_clock":lambda p,s:p.endswith("/bd_22c0_clkwiz_aclk_kernel_00_0.xdc") and "aclk_kernel_00_hierarchy/clkwiz_aclk_kernel_00/inst" in s,
            "clock_control":lambda p,s:p.endswith("/bd_22c0_clock_throttling_aclk_kernel_00_0.xdc") and "aclk_kernel_00_hierarchy/clock_throttling_aclk_kernel_00/U0" in s,
            "axi_clock_conversion":lambda p,s:p.endswith("/ulp_interconnect_axilite_user_imp_auto_cc_0_clocks.xdc") and "interconnect_axilite_user/m00_couplers/auto_cc/inst" in s,
            "platform":lambda p,s:p==str(vpl/".local/hw_platform/tcl_hooks/impl.xdc")}
        missing=[role for role,predicate in roles.items() if not any(predicate(p,s) for p,s in starts)]
        if missing:raise RuntimeError("RM checkpoint warning lacks actual companion constraint evidence: "+", ".join(missing))
    return {"status":"PASS","records":records,"companion_xdc_parses":len(starts),
        "companion_xdc_scope_pairs":companions,"basis":"Historical native implementation log; known critical warnings require separate positive physical gates"}


def write_provenance(state, output, coordinator_sha):
    """Only reached by this build after its snapshot/test/package/link/report phases."""
    required={"snapshot","clock_qualification","axi_test","host_build","package","package_qualification","link",state["signoff_phase"]}
    if not required.issubset(state["completed"]) or state["status"]!="PASS":
        raise RuntimeError("Cannot emit release provenance for an incomplete build")
    verify_phase_artifacts(state,output)
    packaged=packaged_parameters(output/"mmul_sysbase.xo")
    report_dir=Path(state["signoff_directory"])
    review_dir=Path(state["assessment_directory"])
    command=["/opt/xilinx/xrt/bin/xclbinutil","--info","--input",str(output/"mmul_sysbase.xclbin")]
    metadata=run(command,output,"xclbin_metadata")
    text=Path(metadata["log"]).read_text()
    uuid=re.search(r"UUID \(xclbin\):\s*([a-fA-F0-9-]+)",text)
    if not uuid or not re.search(r"Kernels:\s*mmul_sysbase\s*\n",text):
        raise RuntimeError("Built XCLBIN is not the expected SysBase kernel")
    design_paths={"hardware/rtl/src/mmul_sysbase_axis_shell.sv","hardware/rtl/src/mmul_sysbase_core.sv",
        "hardware/rtl/src/mmul_row_sdp_ram.sv","verification/hardware/kernel/mmul_sysbase.sv",
        "verification/hardware/host/checked_host.cpp"}
    design_paths.update("hardware/rtl/src/cornell/systolic/"+n for n in ("SysBase.v","MacNew.v","IntMulBase.v"))
    design_paths.update("hardware/rtl/src/cornell/vc/"+n for n in ("trace.v","muxes.v","arithmetic.v","regs.v","queues.v","regfiles.v"))
    design_inputs=[item for item in state["inputs"] if item["path"] in design_paths]
    if {item["path"] for item in design_inputs}!=design_paths:raise RuntimeError("Snapshot misses a compiled design dependency")
    design_inputs.sort(key=lambda item:item["path"])
    source_digest=hashlib.sha256(json.dumps(design_inputs,sort_keys=True,separators=(",",":")).encode()).hexdigest()
    def evidence(path,kind):return {"kind":kind,"path":str(path.relative_to(ROOT)),"sha256":sha(path)}
    host_source=next(item for item in design_inputs if item["path"]=="verification/hardware/host/checked_host.cpp")
    versions=tool_versions(state,output)
    reviewed_evidence=json.loads((review_dir/"constraint_policy.json").read_text()).get("review_evidence",[])
    for item in reviewed_evidence:
        if sha(ROOT/item["path"])!=item["sha256"]:raise RuntimeError("Vendor review evidence changed before provenance emission")
    record={"schema_version":1,"design_id":"u55c_systolic_mmul.sysbase","kernel":"mmul_sysbase",
        "abi":"u55c_mmul_legacy_a_b_c_dim_v1","parameters":{"MAX_DIM":packaged["MAX_DIM"],"ARRAY_SIZE":packaged["ARRAY_SIZE"]},
        "packaged_parameters":packaged,
        "source_sha256":source_digest,"inputs":design_inputs,
        "xclbin":{"sha256":sha(output/"mmul_sysbase.xclbin"),"uuid":uuid[1].lower(),"platform":PLATFORM},
        "host":{"path":str((output/"sysbase_checked_host").relative_to(ROOT)),"sha256":sha(output/"sysbase_checked_host"),
                "sources":[host_source],"build_command":next(c["command"] for c in state["commands"] if c["label"]=="host_build"),
                "tool_versions":{"compiler":versions["compiler"],"xrt":versions["xrt"]}},
        "build":{"status":"PASS","target":"hw","clock_mhz":150,"commands":state["commands"]+[metadata],
                 "ip_cache":state.get("ip_cache"),
                 "tool_versions":versions,"toolchain":state["toolchain"],
                 "producer":{"name":"sysbase_kernel_build_v1","path":str((output/("coordinator_"+coordinator_sha[:16]+".py")).relative_to(ROOT)),"sha256":coordinator_sha},
                 "source_snapshot":str((output/"source_snapshot").relative_to(ROOT)),
                 "procedure_inputs":state["inputs"],
                 "phase_artifacts":state["phase_artifacts"],"signoff_phase":state["signoff_phase"],"build_directory":str(output.relative_to(ROOT)),
                 "migration":state.get("migration"),
                 "resume_history":state.get("resume_history",[]),
                 "evidence":[evidence(output/"mmul_sysbase.xo","rtl_xo"),evidence(output/"link.log","build_log"),
                   evidence(output/"synthesis_hierarchy.txt","synthesis_hierarchy"),evidence(review_dir/"result.json","implementation_signoff"),
                   evidence(output/"axi_sim/result.json","axi_simulation"),evidence(review_dir/"constraint_policy.json","constraint_policy"),
                   evidence(output/"package_qualification/qualification.txt","package_qualification"),
                   evidence(report_dir/"violations.json","cdc_methodology_findings"),
                   evidence(Path(state["finalization_script"]),"finalization_script")]+
                   [dict(item,kind="vendor_review_evidence") for item in reviewed_evidence]+
                   [dict(path=item["path"],sha256=item["sha256"],kind="build_history") for item in state.get("resume_history",[])],
                 "implementation":state["implementation"]}}
    path=output/"mmul_sysbase.provenance.json"
    path.write_text(json.dumps(record,indent=2)+"\n")
    (output/"mmul_sysbase.provenance.sha256").write_text(sha(path)+"\n")
    return str(path)


def main():
    install_signal_handlers()
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir",required=True,type=Path)
    parser.add_argument("--resume",action="store_true",help="Resume completed phases from this source snapshot")
    parser.add_argument("--ip-cache-from",type=Path,help="Seed a private Vivado-managed IP cache from a previous build")
    parser.add_argument("--migrate-observed-build",type=Path,
                        help="One-time import of hashes captured while a known legacy coordinator was running")
    args=parser.parse_args();output=args.output_dir.resolve()
    coordinator_sha=sha(Path(__file__))
    if not output.is_relative_to(ROOT):parser.error("Build evidence must be inside the project")
    output.mkdir(parents=True,exist_ok=True)
    state_path=output/"build_state.json"
    if any(output.iterdir()) and not args.resume:parser.error("Use an empty output directory")
    previous_state=state_path.read_bytes() if args.resume and state_path.exists() else None
    state=json.loads(previous_state) if previous_state is not None else {
        "status":"RUNNING","design_id":"u55c_systolic_mmul.sysbase","commands":[],"completed":[],"clock_mhz":150}
    state["status"]="RUNNING"
    state.pop("reason",None);state.pop("signal",None)
    snapshot=output/"source_snapshot"
    shutil.copy2(Path(__file__),output/("coordinator_"+coordinator_sha[:16]+".py"))
    def persist():state_path.write_text(json.dumps(state,indent=2)+"\n")
    state_verified=False
    try:
        if args.migrate_observed_build:
            if not args.resume:raise RuntimeError("Observed-build migration requires --resume")
            import_observed_migration(state,output,args.migrate_observed_build.resolve(),state_path)
            state_verified=True
            persist()
        if "snapshot" not in state["completed"]:
            files=sorted(set(list((ROOT/"hardware/rtl/src").rglob("*.v"))+list((ROOT/"hardware/rtl/src").rglob("*.sv"))+
                list(HERE.glob("*.py"))+list(HERE.glob("*.tcl"))+list(HERE.glob("*.sv"))+list(HERE.glob("*.xml"))+list(HERE.glob("*.json"))+
                list((HERE.parent/"host").glob("*.cpp"))+[ROOT/"verification/uvm/run.py",ROOT/"hardware/hls/scripts/u55c_clk_metadata_adapter_workaround.tcl"]))
            state["inputs"]=[]
            for path in files:
                relative=path.relative_to(ROOT);destination=snapshot/relative
                destination.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(path,destination)
                state["inputs"].append({"path":str(relative),"sha256":sha(destination)})
            state["source_sha256"]=hashlib.sha256(json.dumps(state["inputs"],sort_keys=True,separators=(",",":")).encode()).hexdigest()
            state["completed"].append("snapshot");persist()
        for item in state["inputs"]:
            if sha(snapshot/item["path"])!=item["sha256"]:raise RuntimeError("Build snapshot changed: "+item["path"])
        verify_phase_artifacts(state,output)
        state_verified=True
        if previous_state is not None:
            previous_sha=hashlib.sha256(previous_state).hexdigest()
            history=output/"resume_history";history.mkdir(exist_ok=True)
            previous_path=history/("state_"+previous_sha+".json")
            if previous_path.exists() and previous_path.read_bytes()!=previous_state:raise RuntimeError("Resume history collision")
            previous_path.write_bytes(previous_state)
            state.setdefault("resume_history",[]).append({"path":str(previous_path.relative_to(ROOT)),"sha256":previous_sha,
                "previous_status":json.loads(previous_state)["status"],"resumed_utc":time.strftime("%Y-%m-%dT%H:%M:%SZ",time.gmtime()),
                "coordinator_sha256":coordinator_sha})
            persist()
        if "toolchain" not in state["completed"]:
            if "host_build" in state["completed"]:raise RuntimeError("Historical host build has no toolchain capture; explicit observed migration is required")
            state["toolchain"]=capture_toolchain()
            toolchain_path=output/"toolchain.json"
            toolchain_path.write_text(json.dumps(state["toolchain"],indent=2)+"\n")
            state.setdefault("phase_artifacts",{})["toolchain"]={"toolchain.json":sha(toolchain_path)}
            state["completed"].append("toolchain");persist()
        verify_toolchain(state["toolchain"])
        if args.ip_cache_from and "ip_cache_seed" not in state["completed"]:
            source=args.ip_cache_from.resolve()
            if not source.is_dir():raise RuntimeError("IP cache seed directory is missing")
            cache=output/"ip_cache"
            if cache.exists():raise RuntimeError("IP cache destination already exists without a recorded seed")
            shutil.copytree(source,cache)
            records={str(path.relative_to(cache)):sha(path) for path in sorted(cache.rglob("*")) if path.is_file()}
            manifest=output/"ip_cache_seed.json"
            manifest.write_text(json.dumps({"source":str(source),"files":records,
                "scope":"Copied seed only; Vivado validates IP identities and may update this private working cache"},indent=2)+"\n")
            state["ip_cache"]={"path":str(cache),"source":str(source),"manifest":str(manifest),"sha256":sha(manifest)}
            state["phase_artifacts"]["ip_cache_seed"]={"ip_cache_seed.json":sha(manifest)}
            state["completed"].append("ip_cache_seed");persist()
        elif args.ip_cache_from and str(args.ip_cache_from.resolve())!=state["ip_cache"]["source"]:
            raise RuntimeError("IP cache seed cannot change during resume")
        kernel=snapshot/"verification/hardware/kernel"
        def phase(name,command,timeout=600,outputs=None):
            verify_phase_artifacts(state,output)
            if name not in state["completed"]:
                print("START "+name,flush=True)
                state["commands"].append(run(command,output,name,timeout))
                artifacts=outputs if outputs is not None else phase_outputs(name,output)
                state.setdefault("phase_artifacts",{})[name]={str(path.relative_to(output)):sha(path) for path in artifacts}
                state["completed"].append(name);persist()
                print("DONE "+name,flush=True)
        phase("clock_qualification",amd("vivado",["-mode","batch","-source",str(kernel/"qualify_clock.tcl"),
              "-tclargs",str(kernel)]),180,outputs=[output/"clock_qualification.log"])
        if "\nSYSBASE_CLOCK_QUALIFICATION_PASS\n" not in (output/"clock_qualification.log").read_text():
            raise RuntimeError("Native clock API qualification did not pass")
        phase("axi_test",["/usr/bin/python3",str(kernel/"simulate.py"),"--output-dir",str(output/"axi_sim")])
        if json.loads((output/"axi_sim/result.json").read_text())["status"]!="PASS":raise RuntimeError("AXI tests did not pass")
        phase("host_build",["/usr/bin/g++","-std=c++17","-O2","-Wall","-Wextra",
              "-I/opt/xilinx/xrt/include",str(snapshot/"verification/hardware/host/checked_host.cpp"),
              "-L/opt/xilinx/xrt/lib","-Wl,-rpath,/opt/xilinx/xrt/lib","-lxrt_coreutil","-luuid","-o",str(output/"sysbase_checked_host")])
        phase("package",amd("vivado",["-mode","batch","-source",str(kernel/"package.tcl"),"-tclargs",str(snapshot),str(output)]),1800)
        if "package_qualification" not in state["completed"]:unpack_xo(output)
        phase("package_qualification",amd("vivado",["-mode","batch","-source",str(kernel/"qualify_package.tcl"),
              "-tclargs",str(output/"unpacked_xo"),str(output/"package_qualification")]),1800)
        if "Unpacked XO IP synthesis completed" not in (output/"package_qualification/qualification.txt").read_text():
            raise RuntimeError("Unpacked package qualification did not complete")
        config=output/"connectivity.cfg"
        config_content="[connectivity]\nsp=mmul_sysbase_1.a:HBM[0]\nsp=mmul_sysbase_1.b:HBM[1]\nsp=mmul_sysbase_1.c:HBM[2]\n"
        if config.exists() and config.read_text()!=config_content:raise RuntimeError("Connectivity configuration changed")
        if not config.exists():config.write_text(config_content)
        cache_options=["--remote_ip_cache",state["ip_cache"]["path"]] if state.get("ip_cache") else []
        phase("link",amd("v++",["--link","--target","hw","--platform",PLATFORM,"--save-temps"]+cache_options+[
              "--kernel_frequency","150","--vivado.synth.jobs","8","--vivado.impl.jobs","8",
              "--vivado.prop","run.impl_1.STEPS.INIT_DESIGN.TCL.PRE="+str(kernel/"clock_api_compat.tcl"),
              "--vivado.prop","run.impl_1.STEPS.INIT_DESIGN.TCL.POST="+str(kernel/"check_impl_clock.tcl"),
              "--config",str(config),"--linkhook.custom","postSysLink,"+str(snapshot/"hardware/hls/scripts/u55c_clk_metadata_adapter_workaround.tcl"),
              str(output/"mmul_sysbase.xo"),"--output",str(output/"mmul_sysbase.xclbin")]),43200)
        frontend=verify_implementation_frontend(output)
        dcps=list(output.glob("_x/link/vivado/vpl/prj/prj.runs/impl_1/*_routed.dcp"))
        if len(dcps)!=1:raise RuntimeError("Expected exactly one full routed platform DCP")
        # Include the output contract so a prior coordinator that retained fewer
        # reports cannot silently adopt newly discovered report files on resume.
        report_names=("metrics.json","drc.rpt","drc_effective.rpt","drc_checks.json","methodology_initial.rpt","methodology.rpt","check_timing.rpt","timing_summary.rpt",
            "route_status.rpt","bus_skew.rpt","cdc.rpt","utilization.rpt","violations.json",
            "clocks.rpt","clock_interaction.rpt","exception_coverage.rpt","targeted_pcie_timing.rpt","pcie_ref_to_dma_timing.rpt",
            "dma_link_down_endpoint_timing.rpt","targeted_paths.json","irq_structure.json")
        signoff_digest=hashlib.sha256((sha(HERE/"signoff.tcl")+json.dumps(report_names)).encode()).hexdigest()
        signoff_key="signoff_"+signoff_digest[:16]
        finalization_script=output/(signoff_key+".tcl")
        shutil.copy2(HERE/"signoff.tcl",finalization_script)
        state["finalization_script"]=str(finalization_script)
        report_dir=output/signoff_key
        state["signoff_phase"]=signoff_key
        state["signoff_directory"]=str(report_dir)
        reports=[report_dir/n for n in report_names]
        phase(signoff_key,amd("vivado",["-mode","batch","-source",str(finalization_script),"-tclargs",str(dcps[0]),str(report_dir)]),
              1800,outputs=reports+[finalization_script,output/(signoff_key+".log")])
        phase("platform_metadata",["/opt/xilinx/xrt/bin/xclbinutil","--info","--input",str(output/"mmul_sysbase.xclbin")])
        review_dir=report_dir/("review_"+sha(HERE/"constraint_policy.json")[:16]+"_"+coordinator_sha[:16])
        state["assessment_directory"]=str(review_dir)
        state["implementation"]=signoff_status(report_dir,(output/"platform_metadata.log").read_text(),review_dir)
        state["implementation"]["vendor_static_platform"]=verify_vendor_platform(output)
        state["implementation"]["frontend"]=frontend
        (review_dir/"result.json").write_text(json.dumps(state["implementation"],indent=2)+"\n")
        state["status"]="PASS" if state["implementation"]["status"]=="PASS" else "INCOMPLETE"
        state["xclbin"]={"path":str(output/"mmul_sysbase.xclbin"),"sha256":sha(output/"mmul_sysbase.xclbin")}
        if state["status"]!="PASS":state["reason"]="Routed reports need review; hardware artifact exists but release signoff is incomplete"
        else:
            state["provenance"]=write_provenance(state,output,coordinator_sha)
        if STOP_SIGNAL:raise BuildInterrupted(STOP_SIGNAL)
        persist();print(json.dumps({"status":state["status"],"state":str(state_path)}))
        return 0 if state["status"]=="PASS" else 1
    except BuildInterrupted as error:
        state["status"]="INCOMPLETE";state["reason"]=str(error);state["signal"]=error.number
        if state_verified:persist()
        print(json.dumps({"status":"INCOMPLETE","reason":str(error),"signal":error.number}))
        return 128+error.number
    except Exception as error:
        state["status"]="ERROR";state["reason"]=str(error)
        if state_verified:persist()
        else:
            # A rejected resume must not destroy the original state needed for audited migration.
            (output/("rejected_resume_"+str(time.time_ns())+".json")).write_text(json.dumps({"status":"ERROR","reason":str(error)},indent=2)+"\n")
        print(json.dumps({"status":"ERROR","reason":str(error)}))
        return 1


if __name__=="__main__":raise SystemExit(main())
