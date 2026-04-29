#!/bin/bash
log show --predicate 'eventMessage CONTAINS "crash" OR eventMessage CONTAINS "fatal"' --last 15m > crash_logs.txt
grep -i "PriType" crash_logs.txt | head -n 20
