# Submission

Fork URL: <!-- paste the URL of your fork here -->

## Files to commit

- [ ] `notes.md` with your commands and what you saw (optional)

## Questions

Answer in your own words. Where a question asks for output, paste it in a code block.

### Q1. Paste the command that created your flow log and the log format you chose. Why did you add `${action}` and the ports, and what does the default format lack for this investigation? Why `ALL` and not only `REJECT` traffic?

**Your answer:**

<!-- replace this line with your answer -->

### Q2. Paste your Logs Insights query and the rows it returned for the rejected calls from the client to the service. Which destination port was rejected, and which port does the security group open instead?

**Your answer:**

<!-- replace this line with your answer -->

### Q3. Flow logs say REJECT, but not WHY. Name the two kinds of firewall in a VPC that can produce a REJECT and say how you told which one it was here.

**Your answer:**

<!-- replace this line with your answer -->

### Q4. Paste the same query after your fix: the call is now ACCEPT. How long after the fix did the accepts appear in the log, and why is that delay the reason flow logs are not a live monitoring tool?

**Your answer:**

<!-- replace this line with your answer -->

### Q5. Run a Logs Insights query for the busiest rejected sources in the last hour and paste the top five. Who are these addresses, and what does it tell you about a server with a public IP?

**Your answer:**

<!-- replace this line with your answer -->

### Q6. You send flow logs to CloudWatch Logs and set a retention period. What does it cost to keep them forever, and when would you send them to S3 instead?

**Your answer:**

<!-- replace this line with your answer -->

### Q7. Paste the output of `./verify.sh`. It must end with **ALL CHECKS PASSED**.

**Your answer:**

<!-- replace this line with your answer -->

### Q8. **Tear down.** Paste the output of `./verify-teardown.sh`. It must end with **TEARDOWN VERIFIED**.

**Your answer:**

<!-- replace this line with your answer -->
