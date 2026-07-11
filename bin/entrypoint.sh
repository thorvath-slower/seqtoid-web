#!/bin/sh
if test -z "$ENVIRONMENT"; then
    # If ENVIRONMENT not set, assume local development
    export ENVIRONMENT=dev
fi

# Chamber service = the SSM path secrets are loaded from. Defaults to idseq-$ENVIRONMENT-web,
# so an unset CHAMBER_SERVICE is byte-identical to before (dev/staging/prod untouched). A per-PR
# preview sandbox sets CHAMBER_SERVICE to its OWN path (e.g. idseq-sandbox-pr-N-web) so it reads
# its own DB creds -- this is the only reliable DB-isolation lever, because `chamber exec` CLOBBERS
# any chart-injected pod env (an SSM value overwrites a same-named env var), so pointing chamber at
# a different service is the only way to swap the DB the pod connects to.
: "${CHAMBER_SERVICE:=idseq-$ENVIRONMENT-web}"

if [ "$OFFLINE" = "1" ]
then
    exec bundle exec "$@"
else
    # Use Chamber to inject secrets via environment variables.
    exec chamber exec "$CHAMBER_SERVICE" -- bundle exec "$@"
fi
