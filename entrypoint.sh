#!/bin/bash
# Starts the SSH server, then runs whatever command was given (an
# interactive shell by default, or `west build`, etc.). SSH stays available
# whether you get in via `docker compose exec` or `ssh root@localhost -p 2222`.
service ssh start
exec "$@"