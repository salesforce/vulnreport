#!/bin/sh
grep -r --color=always --exclude=start.sh "NOPROD" *
grep -r --color=always --exclude=start.sh "@TODO" *
authbind thin start -p 443 --threaded --ssl --ssl-cert-file server.crt --ssl-key-file server.key
