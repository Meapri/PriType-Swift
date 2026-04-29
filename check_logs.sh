#!/bin/bash
log show --predicate 'process == "PriTypeV2"' --last 15m > pritype_logs.txt
log show --predicate 'eventMessage CONTAINS "PriTypeV2"' --last 15m >> pritype_logs.txt
grep -i "quarantine\|amfi\|crash\|killed\|prevent\|error\|fail" pritype_logs.txt | head -n 20
