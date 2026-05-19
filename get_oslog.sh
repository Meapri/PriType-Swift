#!/bin/bash
log show --predicate 'subsystem == "com.pritype.inputmethod"' --last 15m > oslog.txt
grep -v "Finder" oslog.txt | tail -n 30
