#!/bin/sh

ruby SEED.rb
grep -r --color=always --exclude=start.sh "NOPROD" *
grep -r --color=always --exclude=start.sh "@TODO" *
#authbind
thin start -p 8080 --threaded
#--ssl --ssl-cert-file server.crt --ssl-key-file server.key
