# Lab 1 Report – Loan Approval Automation with Camunda 8

## 1. Objective
Automate a loan approval workflow combining BPMN orchestration, a DMN decision, a Spring Boot external job worker, a REST connector, a human review task, and operational monitoring in Operate. All data is synthetic; the rules are educational.

## 2. Architecture
- **Zeebe/Camunda 8** executes `loan-approval-process` and evaluates DMN `loan_decision`.
- **Spring Boot worker** (port 8081) subscribes to job type `validate-applicant`, and also hosts a **mock credit API** (`POST /api/credit-assessment`).
- **REST connector** (`io.camunda:http-json:1`) calls the mock API from the connector runtime.
- **Tasklist** hosts the start form and the manual-review user task. **Operate** provides monitoring and incident handling.

Data flow: start-form variables → worker adds `validationPassed`, `estimatedMonthlyEmi`, `debtToIncomeRatio`, `loanToAnnualIncome` → connector adds `creditAssessment` → DMN adds `decisionResult` → reviewer adds `reviewerDecision` → script task sets `finalDecision`.

## 3. Implementation summary
1. BPMN with three exclusive gateways (validity, DMN result, reviewer decision), an error boundary event on the REST task, and two end events.
2. DMN, FIRST hit policy, three inputs, two outputs, five rules (see README).
3. Worker validates fields/ranges and computes EMI, DTI and loan-to-income ratio. A configuration flag injects a failure for one applicant to demonstrate recovery.
4. REST failure handling: HTTP errors ≥ 400 are converted to a BPMN error and routed to manual review (conservative fallback); timeouts surface as incidents after retries.
5. Manual review uses a Camunda Form showing applicant data, score, DTI and the DMN reason.

## 4. Results
Fill in after execution (see README test table). Attach Tasklist/Operate screenshots: approved instance, rejected instance, manual-review task, API-error route, timeout incident, worker incident, recovery after retry.

| Scenario | Observed route | Observed outcome |
|---|---|---|
| TC1 Approval | | |
| TC2 / 2b Rejection | | |
| TC3 Manual review | | |
| TC4a / 4b API error / timeout | | |
| TC5 Worker failure and recovery | | |

## 5. Incident investigation and recovery (template)
- Symptom: instance stopped at "Validate applicant" with an incident.
- Diagnosis: Operate incident message shows the worker exception; worker log confirms fault injection enabled.
- Correction: set `fault-injection-enabled=false`, restart worker.
- Recovery: Retry in Operate; job completes; instance reaches End Approved.

## 6. Limitations
- Credit API is a deterministic mock; scores depend on applicant-id prefix, not real risk.
- Rules and thresholds are illustrative and not validated for fairness or regulation; no real lending use.
- No authentication on the mock API; no persistence of the application beyond Camunda's data.
- API failure routes to manual review rather than retrying with backoff; a production design would add retries, circuit breaking and SLAs/timers on the user task.
- Camunda SaaS connectors cannot reach `localhost`; a tunnel or self-managed cluster is required.
- The BPMN was authored programmatically and XML-validated, but not executed against a live cluster by the author; connector/element-template versions and the Spring client package may need adjustment for your cluster version.
- No automated tests (e.g. process-test-coverage, unit tests for EMI) are included.
