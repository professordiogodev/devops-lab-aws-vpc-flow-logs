# LAB | VPC Flow Logs: The Call That Never Arrives

## The situation

**Case file 0412 - "The call that never arrives"**

*Exhibit A.* Two servers in the same subnet. The client calls the service every 15 seconds. Every call fails.

*Exhibit B.* The EC2 console shows both running. Nothing in the application logs says anything useful: the call just waits and times out.

*Exhibit C.* A timeout means a packet vanished somewhere, and in the cloud you cannot run `tcpdump` on the network between two servers.

What you *can* do is ask AWS to write down **every connection the network accepted or rejected**. That is **VPC Flow Logs**. You turn them on, question CloudWatch Logs Insights, identify the exact rejected connection and fix the one wrong rule.

> **Your mission**
> - Build the broken scene and confirm the client reports `call=fail`
> - Send the VPC's flow logs to CloudWatch Logs with a role that can do only that
> - Ask Logs Insights which connections were rejected and read the evidence
> - Fix the firewall, and see the same connection turn from `REJECT` to `ACCEPT` in the log
> - Look at who else knocks on your door, then tear everything down and prove it

**Time:** 60-75 min | **Cost:** a few cents (two small servers for an hour) | **You need:** an AWS administrator user, the AWS CLI v2 configured for it, Python 3 and a terminal.

---

## Part 0 - Set the scene

Fork this repository, clone your fork, and build the network:

```bash
./setup.sh
```

You get one VPC `10.50.0.0/16` with the **client** (`10.50.1.10`) and the **service** (`10.50.1.20`, listens on port **8080**). The client writes the result of its call on **its own tags**: `call` is `ok` or `fail`, and `call-checked` is the time of the last try. Give it two minutes to install its little script, then watch it:

```bash
aws ec2 describe-tags --filters Name=resource-type,Values=instance Name=key,Values=call \
  --query 'Tags[].[ResourceId,Value]' --output text
```

> **Think** `fail` tells you that something is wrong. It does not tell you *where*: the service could be down, the route missing, the client unable to resolve a name, or a firewall could be saying no. List two ways to find out without logging in to either server. We will use the one that works on any network.

---

## Part 1 - Turn on the flow log

A flow log needs three things: **what** to watch (the VPC), **where** to write (a log group) and **who** does the writing (an IAM role the Flow Logs service assumes).

1. Create a CloudWatch **log group** for it, named `/clippy/flowlab` (or starting with that), set a **retention** of 7 days on it (logs kept forever are logs paid for forever) and tag it `lab=aws-vpc-flow-logs`. Teardown finds your resources by that tag.
2. Create the IAM **role**, named `clippy-flowlab-<something>`. Its trust policy lets `vpc-flow-logs.amazonaws.com` assume it; its permissions allow only the `logs:` actions the service needs (`CreateLogStream`, `PutLogEvents`, `DescribeLogStreams`), **on your log group only**. No wildcards. Tag the role `lab=aws-vpc-flow-logs` too.
3. Create the **flow log** on the VPC. Log **ALL** traffic (not only rejected: you will want the accepted version for comparison), use a **custom format** that includes at least the network interface, the source and destination address, the destination port and the action, and set the **maximum aggregation interval to 60 seconds**.

```bash
aws ec2 create-flow-logs --help | less
```

The default aggregation interval is 10 minutes, which is cheaper and much slower. For finding a fault you want the faster one.

> **Predict** The flow log is attached to the VPC, but the records are written per *network interface*. When the client calls the service, how many records do you expect: one per call, one per interface, or something else? Write your guess, then check in Part 2.

Check that it works: `aws ec2 describe-flow-logs` must say `ACTIVE` and `DeliverLogsStatus: SUCCESS`. If the status says failure, read the message: it is almost always the role.

---

## Part 2 - Ask the network what happened

Wait two to three minutes, then open **CloudWatch > Logs Insights**, select your log group and ask:

```text
fields @timestamp, srcaddr, dstaddr, dstport, action
| filter dstport = 8080
| sort @timestamp desc
| limit 20
```

(Custom formats are space-separated, and Logs Insights discovers the field names automatically for the standard names.) The same from the CLI, if you prefer:

```bash
aws logs start-query --log-group-name <your group> --start-time $(( $(date +%s) - 900 )) --end-time $(date +%s) \
  --query-string 'fields @timestamp, srcaddr, dstaddr, dstport, action | filter dstport = 8080 | limit 20'
aws logs get-query-results --query-id <the id it printed>
```

Find the client's calls (add `interfaceId` to the fields: the same call appears on the *client's* network interface as `ACCEPT`, its packet left, and on the *service's* as `REJECT`, the packet was not let in. Which side is the evidence of the fault?). What does the `action` column say? Which destination port are they going to? Now compare it with what the **service's security group** allows:

```bash
aws ec2 describe-security-groups --filters Name=tag:Name,Values=flowlab-service \
  --query 'SecurityGroups[].IpPermissions'
```

> **Think** The flow log said `REJECT`. It did not say *why*. A security group and a network ACL can both reject. How would you tell which one did it here? (Hint: what does a VPC's default network ACL do, and did anybody change it?)

---

## Part 3 - Fix it and watch the log change

Change the service's firewall: the client's security group may reach **port 8080**. Not the whole world, not a CIDR you typed by hand: the **client's security group**. Remove the rule that opens the wrong port.

Watch the client's `call` tag turn `ok` (within 15 seconds), then ask Logs Insights again for the last five minutes, grouped by action:

```text
filter dstport = 8080 and srcaddr = "10.50.1.10"
| stats count(*) by action
```

You should now see both: older `REJECT` records and new `ACCEPT` records for the *same* connection. Look at the time between your fix and the first `ACCEPT` in the log.

> **Think** The fix took effect in seconds; the log needed minutes to show it. Is a flow log a tool for monitoring a live system or for investigating after the fact?

---

## Part 4 - Who else is knocking?

The servers have public IP addresses. Ask the log for the busiest **rejected** sources over the last hour, excluding the lab's own addresses:

```text
filter action = "REJECT" and srcaddr not like /^10\.50\./
| stats count(*) as attempts by srcaddr, dstport
| sort attempts desc
| limit 10
```

Adapt the query until it works (the `like` with a regular expression keeps the lab's own addresses out). The results depend on the minute you run it; on a fresh public address, scanners often find it within the hour. Paste the top five for question 5. Which ports do they try? (SSH is 22.) Your servers had no rule for those ports, so the network rejected the lot for you.

---

## Part 5 - Prove it

```bash
./verify.sh
```

It reads the flow log, the role and its policy, the log group, the **records AWS wrote** (the REJECTs you hunted and the ACCEPTs after your fix), the service's firewall and the client's tag. Fix what is red and run it again until it ends with **ALL CHECKS PASSED**.

> **Stuck?** `DeliverLogsStatus: FAILED`: the role's trust policy names the wrong service, or the policy's resource does not match the log group ARN (it must end in `:*` for the streams). No records after five minutes: the aggregation interval is still 10 minutes, or the client has not started (check the tag `call-checked`). Logs Insights shows nothing: widen the time range at the top right.

---

## Level up (optional)

- Send a second copy of the flow logs to an S3 bucket in Parquet format. What is it good for that Logs Insights is not?
- Add `${pkt-srcaddr}`, `${flow-direction}` and `${tcp-flags}` to the format. What does `tcp-flags` 2 (SYN only) with `REJECT` tell you about a connection attempt?
- Create a CloudWatch **metric filter** on the log group that counts `REJECT` records to port 22, and an alarm on it. This is the beginning of detection.
- Write a Logs Insights query that answers "which server talks to the most different destinations?" What would a compromised server look like in it?

<!-- teardown:start (generated by labs.py, do not edit) -->
## Tear down (mandatory)

Resources left behind cost money, keep doors open and pollute the next lab. Removing what you created is part of the job, so it is part of the submission: **you must prove it is gone**.

Do this **last**, after you have pasted your `verify` output into `SUBMISSION.md` (once you tear down, the lab can no longer be verified).

1. Run `./teardown.sh`. It removes the servers, the network, your flow log, the log group and the role that delivers the logs (all tagged `lab=aws-vpc-flow-logs`).

Then run the proof:

```bash
./verify-teardown.sh
```

It prints a list of checks and must end with **TEARDOWN VERIFIED**. If it reports leftovers, remove them and run it again. Paste the full output in your submission.
<!-- teardown:end -->

<!-- submission:start (generated by labs.py, do not edit) -->
## Submission

Answer the questions in `SUBMISSION.md` in **your fork** (paste output in code blocks where asked), push, then submit the **URL of your fork**.

**Files to commit**

- `notes.md` with your commands and what you saw (optional)

**Questions to answer**

1. Paste the command that created your flow log and the log format you chose. Why did you add `${action}` and the ports, and what does the default format lack for this investigation? Why `ALL` and not only `REJECT` traffic?
2. Paste your Logs Insights query and the rows it returned for the rejected calls from the client to the service. Which destination port was rejected, and which port does the security group open instead?
3. Flow logs say REJECT, but not WHY. Name the two kinds of firewall in a VPC that can produce a REJECT and say how you told which one it was here.
4. Paste the same query after your fix: the call is now ACCEPT. How long after the fix did the accepts appear in the log, and why is that delay the reason flow logs are not a live monitoring tool?
5. Run a Logs Insights query for the busiest rejected sources in the last hour and paste the top five. Who are these addresses, and what does it tell you about a server with a public IP?
6. You send flow logs to CloudWatch Logs and set a retention period. What does it cost to keep them forever, and when would you send them to S3 instead?
7. Paste the output of `./verify.sh`. It must end with **ALL CHECKS PASSED**.
8. **Tear down.** Paste the output of `./verify-teardown.sh`. It must end with **TEARDOWN VERIFIED**.
<!-- submission:end -->
