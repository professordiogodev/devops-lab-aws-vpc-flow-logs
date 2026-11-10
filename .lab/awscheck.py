#!/usr/bin/env python3
import json, os, subprocess, sys, time
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
os.chdir(ROOT)
passed = failed = 0
L = "aws-vpc-flow-logs"


def check(desc, ok, hint=""):
    global passed, failed
    if ok:
        passed += 1; print("PASS  " + desc)
    else:
        failed += 1; print("FAIL  " + desc + (("   -> " + hint) if hint else ""))


def aws(*a):
    try:
        return json.loads(subprocess.check_output(("aws",) + a + ("--output", "json"), stderr=subprocess.DEVNULL, timeout=90) or "null")
    except Exception:
        return None


def finish():
    print()
    print(("ALL CHECKS PASSED (%d/%d)" % (passed, passed)) if failed == 0 else ("%d check(s) failed, %d passed" % (failed, passed)))
    sys.exit(1 if failed else 0)


acct = subprocess.check_output(["aws", "sts", "get-caller-identity", "--query", "Account", "--output", "text"]).decode().strip()
print("Account %s, region %s" % (acct, subprocess.run(["aws", "configure", "get", "region"], capture_output=True, text=True).stdout.strip() or "us-east-1"))
F = "Name=tag:lab,Values=" + L
vpcs = (aws("ec2", "describe-vpcs", "--filters", F) or {}).get("Vpcs", [])
check("the lab network exists (run ./setup.sh)", len(vpcs) == 1)
if not vpcs:
    finish()
vid = vpcs[0]["VpcId"]
ins = {}
for r in (aws("ec2", "describe-instances", "--filters", F, "Name=instance-state-name,Values=running") or {}).get("Reservations", []):
    for i in r["Instances"]:
        t = {x["Key"]: x["Value"] for x in i.get("Tags", [])}
        ins[t.get("Name")] = (i, t)
check("both servers are running", "flowlab-client" in ins and "flowlab-service" in ins)
if "flowlab-client" not in ins or "flowlab-service" not in ins:
    finish()
cli, ct = ins["flowlab-client"]; svc, st = ins["flowlab-service"]

print("== The flow log ==")
fls = (aws("ec2", "describe-flow-logs", "--filter", "Name=resource-id,Values=" + vid) or {}).get("FlowLogs", [])
check("one flow log is attached to the lab VPC", len(fls) == 1)
fl = fls[0] if fls else {}
check("it is ACTIVE and delivering to CloudWatch Logs without errors", fl.get("FlowLogStatus") == "ACTIVE" and fl.get("LogDestinationType") == "cloud-watch-logs" and fl.get("DeliverLogsStatus") == "SUCCESS", "status: %s / %s" % (fl.get("FlowLogStatus"), fl.get("DeliverLogsStatus")))
check("it logs ALL traffic (accepted and rejected)", fl.get("TrafficType") == "ALL")
fmt = fl.get("LogFormat", "")
need = ["${interface-id}", "${srcaddr}", "${dstaddr}", "${dstport}", "${action}"]
check("the log format has the interface, source, destination, destination port and action", all(n in fmt for n in need), "default format lacks nothing here, but a custom one must keep these four")
check("aggregation interval is 60 seconds (so this lab does not wait 10 minutes)", fl.get("MaxAggregationInterval") == 60)
lg = fl.get("LogGroupName")
groups = (aws("logs", "describe-log-groups", "--log-group-name-prefix", lg) or {}).get("logGroups", []) if lg else []
grp = next((g for g in groups if g["logGroupName"] == lg), None)
check("the log group name starts with /clippy/flowlab (teardown finds it by name)", (lg or "").startswith("/clippy/flowlab"))
check("the log group exists and keeps logs for a set number of days (not forever)", bool(grp) and "retentionInDays" in grp)
tg = {}
if grp:
    tg = (aws("logs", "list-tags-for-resource", "--resource-arn", grp["arn"].rstrip(":*")) or {}).get("tags", {})
check("the log group is tagged lab=%s (teardown finds it by the tag)" % L, tg.get("lab") == L)
role_arn = fl.get("DeliverLogsPermissionArn", "")
rname = role_arn.split("/")[-1]
role = (aws("iam", "get-role", "--role-name", rname) or {}).get("Role") if rname else None
rtags = {t["Key"]: t["Value"] for t in (role or {}).get("Tags", [])}
check("the delivery role is tagged lab=%s and its name starts with clippy-flowlab" % L, rtags.get("lab") == L and rname.startswith("clippy-flowlab"))
trust = json.dumps((role or {}).get("AssumeRolePolicyDocument", {}))
check("only the flow logs service can assume the delivery role", "vpc-flow-logs.amazonaws.com" in trust and "ec2.amazonaws.com" not in trust)
acts, res = [], []
for p in (aws("iam", "list-role-policies", "--role-name", rname) or {}).get("PolicyNames", []) if rname else []:
    doc = (aws("iam", "get-role-policy", "--role-name", rname, "--policy-name", p) or {}).get("PolicyDocument", {})
    for s in doc.get("Statement", []) if isinstance(doc.get("Statement"), list) else [doc.get("Statement", {})]:
        a = s.get("Action", []); r = s.get("Resource", [])
        acts += [a] if isinstance(a, str) else a
        res += [r] if isinstance(r, str) else r
check("the role's policy has no wildcard action and is limited to logs actions", bool(acts) and all(x.startswith("logs:") and "*" not in x for x in acts), ", ".join(acts)[:100])
check("the policy's resource is the log group, not *", bool(res) and "*" not in res and all(lg in x for x in res if lg), ", ".join(res)[:100])

print("== The investigation ==")
cip, sip = cli["PrivateIpAddress"], svc["PrivateIpAddress"]
fields = [f.strip("${}") for f in fmt.split()] if fmt else []


def events(pattern, window_min=60):
    out = []
    try:
        r = aws("logs", "filter-log-events", "--log-group-name", lg, "--filter-pattern", pattern, "--start-time", str(int((time.time() - window_min * 60) * 1000)), "--limit", "200")
        out = [e["message"].split() for e in (r or {}).get("events", [])]
    except Exception:
        pass
    return out


def field(rec, name):
    try:
        return rec[fields.index(name)]
    except (ValueError, IndexError):
        return None


seni = {e["NetworkInterfaceId"] for e in svc.get("NetworkInterfaces", [])}
rej = [r for r in events('"REJECT" "8080"') if field(r, "interface-id") in seni and field(r, "srcaddr") == cip and field(r, "dstaddr") == sip and field(r, "dstport") == "8080" and field(r, "action") == "REJECT"] if lg and fields else []
check("the log shows the client's calls to %s:8080 as REJECT at the service's network interface (the evidence you were hunting)" % sip, len(rej) > 0, "turn the flow log on, wait 2-3 minutes with the client calling")
sgs = (aws("ec2", "describe-security-groups", "--group-ids", *[g["GroupId"] for g in svc["SecurityGroups"]]) or {}).get("SecurityGroups", [])
perms = [p for g in sgs for p in g["IpPermissions"]]
p8080 = [p for p in perms if p.get("FromPort") == 8080 and p.get("ToPort") == 8080]
ok_src = len(p8080) == 1 and not any(r["CidrIp"] == "0.0.0.0/0" for r in p8080[0].get("IpRanges", [])) and (
    {x["GroupId"] for x in p8080[0].get("UserIdGroupPairs", [])} & {g["GroupId"] for g in cli["SecurityGroups"]} or any(r["CidrIp"] in (cip + "/32",) for r in p8080[0].get("IpRanges", [])))
check("the service's firewall now allows 8080 from the client only (not from the world)", ok_src)
check("the wrong rule for 8081 is gone", not [p for p in perms if p.get("FromPort") == 8081])
acc = [r for r in events('"ACCEPT" "8080"', 30) if field(r, "interface-id") in seni and field(r, "srcaddr") == cip and field(r, "dstaddr") == sip and field(r, "dstport") == "8080" and field(r, "action") == "ACCEPT"] if lg and fields else []
check("the log now shows ACCEPT for the same call at the service's network interface", len(acc) > 0, "after the fix the accepts take 1-3 minutes to appear")
alltags = {x["Key"]: x["Value"] for x in (aws("ec2", "describe-tags", "--filters", "Name=resource-id,Values=" + cli["InstanceId"]) or {}).get("Tags", [])}
check("the client reports call=ok on its own tags", alltags.get("call") == "ok", "call=%s" % alltags.get("call"))
finish()
