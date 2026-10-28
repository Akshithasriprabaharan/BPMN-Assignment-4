#!/usr/bin/env bash
# Starts one process instance per scenario using the Camunda 8.8 REST API (v2).
# Self-managed / Camunda 8 Run: default demo:demo. Adjust BASE and AUTH for your cluster.
BASE=${BASE:-http://localhost:8080}
AUTH=${AUTH:-demo:demo}

start() { # id name age emp income debt amount term
  curl -s -u "$AUTH" -X POST "$BASE/v2/process-instances" -H 'Content-Type: application/json' -d "{
    \"processDefinitionId\": \"loan-approval-process\",
    \"variables\": {\"applicantId\":\"$1\",\"applicantName\":\"$2\",\"age\":$3,\"employmentStatus\":\"$4\",
      \"monthlyIncome\":$5,\"existingMonthlyDebt\":$6,\"loanAmount\":$7,\"loanTermMonths\":$8,\"loanPurpose\":\"Synthetic test\"}}"
  echo; }

echo "TC1 approve";            start A1001   "Asha Rao"      32 SALARIED 100000  5000 300000 36
echo "TC2 reject (DMN)";       start C3001   "Chitra Das"    40 SALARIED  60000  8000 200000 36
echo "TC2b reject (validation)"; start A1002 "Minor Test"    17 SALARIED  50000     0 100000 24
echo "TC3 manual review";      start B2001   "Bala Kumar"    45 SALARIED  80000 10000 500000 60
echo "TC4a credit API 500";    start ERR9001 "Err Test"      35 SALARIED  90000  2000 200000 36
echo "TC4b credit API timeout";start SLOW9001 "Slow Test"    35 SALARIED  90000  2000 200000 36
echo "TC5 worker failure";     start A9999 "Fail Test"     30 SALARIED  70000     0 150000 24
