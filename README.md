# Lab 1 – End-to-End Loan Approval Automation (Camunda 8)

Synthetic data only. Educational rules, not real lending policy.

## 1. Files

| File                               | Purpose                                       |
|------------------------------------|-----------------------------------------------|
| `bpmn/loan-approval.bpmn`          | BPMN process `loan-approval-process`          |
| `dmn/loan-decision.dmn`            | DMN decision table `loan_decision`            |
| `forms/loan-application-form.form` | Start form (Tasklist "Start process")         |
| `forms/manual-review-form.form`    | Manual-review user-task form                  |
| `worker/`                          | Spring Boot app: job worker + mock credit API |
| `tests/start-instances.sh`         | Starts all test instances via REST API        |

## 2. Architecture

```
Start (form) -> [Validate applicant: job worker "validate-applicant"] -> <valid?>
   invalid -> Record Rejected -> End Rejected
   valid   -> [Credit assessment: REST connector -> POST /api/credit-assessment]
                 | error boundary (HTTP >= 400) -> Manual review
              -> [Business rule task: DMN loan_decision] -> <decision?>
                    Approved -> Record Approved -> End Approved
                    Rejected -> Record Rejected -> End Rejected
                    Manual Review -> [User task: Manual review (Tasklist)] -> <reviewer decision?>
                                         Approve -> Record Approved ; otherwise -> Record Rejected
```

## 3. DMN decision table (`loan_decision`, hit policy FIRST)

Inputs: `creditAssessment.creditScore` (REST), `debtToIncomeRatio` (%, worker), `loanToAnnualIncome` (x, worker).
Outputs: `decision` (Approved / Rejected / Manual Review), `reason`.

| # | Credit score | DTI % | Loan / annual income | Decision | Reason |
|---|---|---|---|---|---|
| 1 | < 550 | – | – | Rejected | Credit score below 550 |
| 2 | – | > 50 | – | Rejected | DTI above 50% |
| 3 | – | – | > 8 | Rejected | Loan exceeds 8x annual income |
| 4 | >= 700 | <= 40 | <= 5 | Approved | Meets all approval criteria |
| 5 | – | – | – | Manual Review | Borderline profile |

Worker validation rules (before any credit call): all fields present; age 18–70; not UNEMPLOYED; monthly income >= 15,000; loan 10,000–5,000,000; term 6–84 months.
EMI = P·r / (1 − (1+r)^−n), r = 12%/12. DTI = (existing debt + EMI) / monthly income × 100.

Sample evaluations: (780, 15, 0.25) → Approved · (520, 20, 0.3) → Rejected (rule 1) · (650, 26.4, 0.52) → Manual Review · (720, 55, 1) → Rejected (rule 2) · (720, 38, 6) → Manual Review.

## 4. REST integration example

Connector: `io.camunda:http-json:1`, `POST http://localhost:8081/api/credit-assessment`, connect timeout 5 s, read timeout 10 s.

Request body (FEEL mapping `{applicantId, loanAmount, monthlyIncome}`):
```json
{ "applicantId": "A1001", "loanAmount": 300000, "monthlyIncome": 100000 }
```
Response 200:
```json
{ "applicantId": "A1001", "creditScore": 780, "riskLevel": "LOW", "reportId": "3f1c…" }
```
Stored as `creditAssessment = {creditScore, riskLevel, reportId}` via `resultExpression`.
Response 500 → `errorExpression` throws BPMN error `CREDIT_API_ERROR` → boundary event → Manual review.
Timeout (applicantId `SLOW…`) → connector job fails → retries (3) → **incident** in Operate.

Mock data rules: id prefix `A`=780, `B`=650, `C`=520, `ERR`=HTTP 500, `SLOW`=15 s delay, other=pseudo-random 400–799.
The Camunda SaaS connector runtime cannot reach `localhost`; use self-managed/Camunda 8 Run, or tunnel port 8081 (ngrok) and edit the URL in the task.

## 5. Process variables

| Variable | Set by | Type |
|---|---|---|
| applicantId, applicantName, employmentStatus, loanPurpose | Start form | string |
| age, monthlyIncome, existingMonthlyDebt, loanAmount, loanTermMonths | Start form | number |
| validationPassed, validationErrors, validatedAt | Worker | boolean, list, string |
| estimatedMonthlyEmi, debtToIncomeRatio, loanToAnnualIncome | Worker | number |
| creditAssessment {creditScore, riskLevel, reportId} | REST connector | object |
| decisionResult {decision, reason} | DMN | object |
| reviewerDecision, reviewerComments | Manual review form | string |
| finalDecision | Script task | Approved / Rejected |

## 6. Setup and run

1. Start Camunda 8 (Camunda 8 Run: `./start.sh`, or SaaS cluster). Create the connector secrets/runtime if self-managed (bundled in Run).
2. Edit `worker/src/main/resources/application.yml` (connection block A or B).
3. `cd worker && mvn spring-boot:run` (Java 17+). Worker and mock API run on port 8081. Adjust `camunda.version` in `pom.xml` to match your cluster; this code uses the 8.8 `io.camunda.client` package (for 8.6/8.7 use `spring-boot-starter-camunda` and `io.camunda.zeebe.spring.client.annotation.JobWorker`).
4. Open Web Modeler or Desktop Modeler, deploy **together**: `loan-approval.bpmn`, `loan-decision.dmn`, both `.form` files.
5. Run `tests/start-instances.sh` (set `BASE`/`AUTH`), or start manually from Tasklist → Processes → Loan Approval Process using the start form.
6. Tasklist: open the "Manual review" task, claim/assign it, choose Approve/Reject, complete.
7. Operate: inspect instance history, variables, flow-node states.

Note: `.bpmn` is authored by hand for the 8.6+ schema. If the Modeler shows the connector task without its template UI, apply the **REST Outbound Connector** template to the task; the values are already set. Tasks are unassigned; optionally add an assignee or candidate group in the user task's Assignment section.

## 7. Failure exercise (scenario 5)

1. Set `loan.worker.fault-injection-enabled: true`, restart the worker.
2. Start instance with `applicantId=A9999` (script test TC5). The worker throws; after 3 retries an incident is raised at "Validate applicant".
3. Operate → instance → incident message "Simulated validation-service outage…" (screenshot).
4. Fix: set `fault-injection-enabled: false`, restart the worker.
5. Operate → Retry the incident (or "Retry" on the job). Instance continues → Approved (screenshot).

Credit timeout (TC4b): incident at the REST task; fix by choosing a non-SLOW applicant via *Modify process instance* / variable edit (`applicantId` → `A1001`) in Operate, then Retry. Edit variable first, then retry.

## 8. Test-case table (fill Actual/Status after running)

| TC | Input (id, age, income, debt, amount, term) | Expected route | Expected outcome | Actual | Status |
|---|---|---|---|---|---|
| 1 | A1001, 32, 100000, 5000, 300000, 36 | Validate → Credit(780) → DMN rule 4 | finalDecision = Approved | | |
| 2 | C3001, 40, 60000, 8000, 200000, 36 | Validate → Credit(520) → DMN rule 1 | Rejected | | |
| 2b | A1002, age 17 | Validate fails → Record Rejected (no credit call) | Rejected, validationErrors set | | |
| 3 | B2001, 45, 80000, 10000, 500000, 60 | DMN rule 5 → User task → reviewer | Reviewer's choice | | |
| 4a | ERR9001, 35, 90000, 2000, 200000, 36 | Credit HTTP 500 → boundary → User task | Manual review | | |
| 4b | SLOW9001, same | Credit read timeout → retries → incident | Incident at REST task | | |
| 5 | A9999 with fault injection on | Worker incident → fix → retry → rule 4 | Approved after recovery | | |

## 9. Screenshot checklist
Tasklist: start form; manual-review task list; completed review. Operate: process diagram with token counts; instance variables; TC4b/TC5 incident panel; same instance after retry. Save into `screenshots/`.
