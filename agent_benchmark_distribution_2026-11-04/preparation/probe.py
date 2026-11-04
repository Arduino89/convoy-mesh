"""No-paid-API preparation checks; deliberately cannot launch the benchmark."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--runtime", type=Path, required=True, help="External npm install directory")
parser.add_argument("--evidence", type=Path, required=True, help="Destination JSON, outside runtime")
args = parser.parse_args()
runtime = args.runtime.resolve()
dsh = runtime / "node_modules/.bin/dsh"
package = json.loads((runtime / "node_modules/@deepseek-ai/dsh/package.json").read_text())
if package["version"] != "0.2.1-rc.5":
    raise SystemExit("Unexpected Harness version; review before changing the pin")
node = shutil.which("node")
if not node:
    raise SystemExit("Node.js missing")

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

checks = []
with tempfile.TemporaryDirectory(prefix="convoy-harness-preparation-") as temp:
    # No ambient secrets, provider profiles, .env files or user config inherited.
    # Empty DEEPSEEK_API_KEY explicitly shadows Harness .env fallbacks.
    env = {"PATH": os.environ["PATH"], "LANG": "C.UTF-8", "DSH_HOME": temp + "/state",
           "TMPDIR": temp, "DEEPSEEK_API_KEY": "", "DSH_PERMISSION_MODE": "read-only",
           "DSH_TELEMETRY_MODE": "OFF"}

    def run(name, command, expected):
        result = subprocess.run(command, cwd=temp, env=env, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=45)
        stdout = result.stdout.replace(temp, "<TEMP>").replace(str(runtime), "<RUNTIME>")
        stderr = result.stderr.replace(temp, "<TEMP>").replace(str(runtime), "<RUNTIME>")
        check = {"name": name,
                 "argv": [str(part).replace(temp, "<TEMP>").replace(str(runtime), "<RUNTIME>")
                          for part in command],
                 "cwd": "<TEMP>", "exit_code": result.returncode,
                 "stdout": stdout, "stderr": stderr,
                 "pass": expected(result.returncode, result.stdout, result.stderr)}
        checks.append(check)
        return result

    run("version", [str(dsh), "--version"], lambda rc, out, err: rc == 0 and out.strip() == "0.2.1-rc.5")
    run("headless_help", [str(dsh), "headless", "--help"], lambda rc, out, err: rc == 0 and "--json" in out)
    composed = run("compose_read_only", [str(dsh), "headless", "--patch", str(HERE / "read-only.patch.yml"), "--dump-config"],
                   lambda rc, out, err: rc == 0 and "mode: read-only" in out)
    # Full composed tree is recoverable by rerunning. Preserve its hash, not a duplicate.
    checks[-1]["stdout_sha256"] = hashlib.sha256(composed.stdout.encode()).hexdigest()
    checks[-1]["stdout"] = "Composed tree omitted; rerun --dump-config to inspect."
    run("missing_key_fails_closed", [str(dsh), "headless", "--patch", str(HERE / "read-only.patch.yml"),
                                     "--json", "Preparation smoke only. Reply READY. Do not use tools."],
        lambda rc, out, err: rc == 1 and '"code":"MISSING_CREDENTIAL"' in out and "did not activate" not in err)
    services = run("local_harness_services", [node, str(HERE / "runtime_probe.mjs"), str(runtime), shutil.which("python3")],
                   lambda rc, out, err: rc == 0 and json.loads(out)["mcp"]["state"] == "PASS")

report = {
    "schema": 1, "observed_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "harness_version": package["version"], "node_version": subprocess.check_output([node, "--version"], text=True).strip(),
    "benchmark_state": "NOT_RUN", "paid_inference_requests": 0, "api_spend_usd": 0,
    "deepseek_api_authentication": "NOT_TESTED", "github_mcp_live": "NOT_CONFIGURED",
    "source_hashes": {p.name: sha(p) for p in [HERE / "probe.py", HERE / "runtime_probe.mjs", HERE / "mcp_fixture.py", HERE / "read-only.patch.yml"]},
    "checks": checks,
}
if services.returncode == 0:
    report["services"] = json.loads(services.stdout)
args.evidence.parent.mkdir(parents=True, exist_ok=True)
args.evidence.write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps({"checks_passed": sum(c["pass"] for c in checks), "checks_total": len(checks),
                  "evidence": str(args.evidence), "services": report.get("services")}, indent=2))
raise SystemExit(0 if all(c["pass"] for c in checks) else 1)
