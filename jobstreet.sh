#!/usr/bin/env bash
# =============================================================================
# CAREER INTELLIGENCE ENGINE v12.8 – PIPE‑DELIMITED ACQUISITION
# Architecture: Acquire → Normalize → Observe → Resolve → Infer → Query → Notify
# =============================================================================
# FIXES in v12.8:
# - Acquisition now uses the Python scraper in its default pipe‑delimited mode.
# - No --json flag needed – avoids JSON parsing errors.
# - Each job line is converted to JSON inside the Bash script.
# - All previous classifier and database fixes retained.
# =============================================================================

set -Euo pipefail

# -----------------------------------------------------------------------------
# CONFIGURATION
# -----------------------------------------------------------------------------
CIE_DB_DIR="${HOME}/Documents/bin"
CIE_DB_NAME="cie.db"
CIE_DB_PATH="${CIE_DB_DIR}/${CIE_DB_NAME}"
CIE_LOG_DIR="${HOME}/scriptlogs/cie"
CIE_EMAIL_TO="cabpacedilla@gmail.com"
CIE_SMTP_ACCOUNT="default"
CIE_MAX_RECOMMENDATIONS=20
CIE_CUTOFF_MINUTES=1440
CIE_LOCK_FILE="${CIE_DB_DIR}/cie_engine.lock"
CIE_RETENTION_DAYS=365
CIE_LOG_RETENTION_DAYS=90
CIE_CLASSIFIER_NAME="domain_classifier"
CIE_CLASSIFIER_VERSION="1.0"
CIE_MAX_RETRIES=5
CIE_MIN_SQLITE_VERSION="3.35.0"
LOCK_HELD=false

# Python scraper location
CIE_SCRAPER="${CIE_DB_DIR}/find_jobs.py"

# -----------------------------------------------------------------------------
# KEYWORDS (copied from visa_job_search.sh)
# -----------------------------------------------------------------------------
readonly QA_KEYWORDS=(
    "QA" "Quality Assurance" "Quality Engineer" "Test Engineer" "Software Test"
    "SDET" "Automation Test" "Test Automation" "Quality Engineering"
    "Senior QA" "Senior Quality Engineer" "Senior SDET"
    "QA Lead" "Senior QA Lead" "Lead QA Engineer" "QA Manager" "Quality Assurance Manager"
    "Test Architect" "QA Architect" "Test Automation Architect" "Quality Engineering Architect"
    "Hardware QA" "Firmware Test" "Integration Test" "Embedded QA" "Systems QA"
    "AI QA" "ML Test Engineer" "Fintech QA" "Payments QA"
)

mkdir -p "${CIE_DB_DIR}" "${CIE_LOG_DIR}"

# -----------------------------------------------------------------------------
# DEPENDENCY CHECK
# -----------------------------------------------------------------------------
_check_dependencies() {
    local deps=("sqlite3" "jq" "perl" "flock" "msmtp" "gawk" "md5sum" "python3")
    local missing=()
    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "ERROR: Missing required dependencies: ${missing[*]}" >&2
        exit 1
    fi
    if [[ ! -f "$CIE_SCRAPER" ]]; then
        echo "ERROR: Scraper script not found: $CIE_SCRAPER" >&2
        exit 1
    fi
    if ! python3 -c "import playwright" 2>/dev/null; then
        echo "ERROR: Playwright not installed. Run: pip install playwright && playwright install chromium" >&2
        exit 1
    fi
}

_check_dependencies

# -----------------------------------------------------------------------------
# SQLITE VERSION CHECK
# -----------------------------------------------------------------------------
_check_sqlite_version() {
    local version
    version=$(sqlite3 ":memory:" "SELECT sqlite_version();" 2>/dev/null)
    if [[ -z "$version" ]]; then
        echo "ERROR: Could not determine SQLite version." >&2
        exit 1
    fi
    local required="$CIE_MIN_SQLITE_VERSION"
    if ! awk -v req="$required" -v ver="$version" '
        BEGIN {
            split(ver,a,"."); split(req,b,".");
            for(i=1;i<=3;i++) {
                a[i]+=0; b[i]+=0;
                if(a[i] < b[i]) exit 1;
                if(a[i] > b[i]) exit 0;
            }
            exit 0;
        }'; then
        echo "ERROR: SQLite version $version is below required $required." >&2
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# HELPERS
# -----------------------------------------------------------------------------
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" >&2
    echo "$msg" >> "${CIE_LOG_DIR}/cie_$(date +%Y%m%d).log"
}

sql_quote() {
    printf '%s' "$1" | sed "s/'/''/g"
}

# -----------------------------------------------------------------------------
# LOCKING
# -----------------------------------------------------------------------------
_acquire_lock() {
    exec 200>"$CIE_LOCK_FILE"
    if ! flock -n 200; then
        log "ERROR: Another instance is running. Exiting."
        return 1
    fi
    LOCK_HELD=true
    log "Lock acquired."
    return 0
}

_release_lock() {
    if $LOCK_HELD; then
        flock -u 200 2>/dev/null || true
        exec 200>&- 2>/dev/null || true
        LOCK_HELD=false
        log "Lock released."
    fi
}
trap '_release_lock' EXIT INT TERM

# -----------------------------------------------------------------------------
# CACHED TAXONOMY & CLASSIFIERS
# -----------------------------------------------------------------------------
declare -A CIE_TAXONOMY
declare -A CIE_CLASSIFIERS

_cache_taxonomy() {
    while IFS='|' read -r id name; do
        CIE_TAXONOMY["$name"]="$id"
    done < <(sqlite3 "$CIE_DB_PATH" "SELECT id, name FROM taxonomy;")
}

_cache_classifiers() {
    while IFS='|' read -r id name version; do
        CIE_CLASSIFIERS["$name|$version"]="$id"
    done < <(sqlite3 "$CIE_DB_PATH" "SELECT id, name, version FROM classifiers;")
}

_get_concept_id() { echo "${CIE_TAXONOMY[$1]:-}"; }
_get_classifier_id() { echo "${CIE_CLASSIFIERS["$1|$2"]:-}"; }

# -----------------------------------------------------------------------------
# MIGRATION APPLICATION
# -----------------------------------------------------------------------------
_apply_migration() {
    local version="$1"
    local sql="$2"
    local applied
    applied=$(sqlite3 "$CIE_DB_PATH" "SELECT 1 FROM schema_version WHERE version='$version';" 2>/dev/null)
    if [[ -n "$applied" ]]; then
        return 0
    fi

    local cleaned_sql
    cleaned_sql=$(echo "$sql" | sed 's/--.*$//g' | perl -0777 -pe 's/\/\*.*?\*\///gs')

    if echo "$cleaned_sql" | grep -qiE '\<(BEGIN|COMMIT|ROLLBACK)\>'; then
        log "ERROR: Migration $version contains transaction control statements."
        exit 1
    fi

    log "Applying migration $version"
    if sqlite3 "$CIE_DB_PATH" <<EOF
BEGIN;
$sql;
INSERT INTO schema_version (version, applied_at) VALUES ('$version', datetime('now'));
COMMIT;
EOF
    then
        log "Migration $version applied."
    else
        log "ERROR: Migration $version failed."
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# DATABASE
# -----------------------------------------------------------------------------
_db_init() {
    log "Initialising database..."
    _check_sqlite_version

    if sqlite3 "$CIE_DB_PATH" <<'EOF'
PRAGMA journal_mode=WAL;
PRAGMA synchronous=NORMAL;
PRAGMA foreign_keys=ON;
PRAGMA busy_timeout=5000;

CREATE TABLE IF NOT EXISTS schema_version (version TEXT PRIMARY KEY, applied_at TEXT);
CREATE TABLE IF NOT EXISTS data_bootstrap (key TEXT PRIMARY KEY, value TEXT);
EOF
    then
        log "Base schema created."
    else
        log "ERROR: Failed to create base schema."
        exit 1
    fi

    sqlite3 "$CIE_DB_PATH" "PRAGMA wal_checkpoint(PASSIVE);" >/dev/null 2>&1
    local integrity
    integrity=$(sqlite3 "$CIE_DB_PATH" "PRAGMA integrity_check;" 2>/dev/null)
    if [[ "$integrity" != "ok" ]]; then
        log "ERROR: Database integrity check failed: $integrity"
        exit 1
    fi

    # ---- Migrations ----
    _apply_migration "001" "
CREATE TABLE IF NOT EXISTS taxonomy (id INTEGER PRIMARY KEY, concept_type TEXT NOT NULL, name TEXT NOT NULL UNIQUE);
CREATE TABLE IF NOT EXISTS classifiers (id INTEGER PRIMARY KEY, name TEXT NOT NULL, version TEXT NOT NULL, rule_hash TEXT, description TEXT, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, UNIQUE(name, version));
CREATE TABLE IF NOT EXISTS companies (id INTEGER PRIMARY KEY, name TEXT UNIQUE NOT NULL, website TEXT, first_seen TIMESTAMP, last_seen TIMESTAMP);
CREATE TABLE IF NOT EXISTS evidence (id INTEGER PRIMARY KEY, subject_type TEXT NOT NULL, subject_id INTEGER NOT NULL, source_system TEXT NOT NULL, source_type TEXT NOT NULL, source_url TEXT, captured_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, raw_text TEXT NOT NULL, UNIQUE(subject_type, subject_id, source_url, raw_text));
CREATE TABLE IF NOT EXISTS observations (id INTEGER PRIMARY KEY, evidence_id INTEGER NOT NULL, classifier_id INTEGER NOT NULL, observation_type TEXT NOT NULL, matched_text TEXT NOT NULL, UNIQUE(evidence_id, classifier_id, observation_type, matched_text), FOREIGN KEY(evidence_id) REFERENCES evidence(id) ON DELETE CASCADE);
CREATE TABLE IF NOT EXISTS resolutions (id INTEGER PRIMARY KEY, observation_id INTEGER NOT NULL, concept_id INTEGER NOT NULL, resolver_version TEXT NOT NULL, taxonomy_version TEXT NOT NULL, resolved_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, UNIQUE(observation_id, concept_id), FOREIGN KEY(observation_id) REFERENCES observations(id) ON DELETE CASCADE, FOREIGN KEY(concept_id) REFERENCES taxonomy(id));
CREATE TABLE IF NOT EXISTS career_phases (id INTEGER PRIMARY KEY, company TEXT, role TEXT, years TEXT, context TEXT, UNIQUE(company, role, years));
CREATE TABLE IF NOT EXISTS jobs (id TEXT PRIMARY KEY, evidence_id INTEGER NOT NULL, company_id INTEGER NOT NULL, posted_date TIMESTAMP, seen_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP, FOREIGN KEY(evidence_id) REFERENCES evidence(id) ON DELETE CASCADE, FOREIGN KEY(company_id) REFERENCES companies(id) ON DELETE CASCADE);
CREATE TABLE IF NOT EXISTS events (id INTEGER PRIMARY KEY, timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP, event_type TEXT NOT NULL, subject_type TEXT, subject_id TEXT, payload TEXT);
CREATE TABLE IF NOT EXISTS unknown_observations (id INTEGER PRIMARY KEY, observation_id INTEGER NOT NULL UNIQUE, matched_text TEXT, reason TEXT, seen_count INTEGER DEFAULT 1, last_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP, FOREIGN KEY(observation_id) REFERENCES observations(id) ON DELETE CASCADE);
CREATE TABLE IF NOT EXISTS maintenance_state (key TEXT PRIMARY KEY, value TEXT);
"

    _apply_migration "002" "
INSERT INTO taxonomy (concept_type, name) VALUES
('industry','Medical Devices'),('industry','Consumer Electronics'),('industry','Industrial Automation'),('industry','Semiconductor'),('industry','FinTech'),('industry','Enterprise Software'),
('domain','Embedded'),('domain','Robotics'),('domain','Firmware'),('domain','Hardware-Integration'),('domain','AI'),('domain','Computer Vision'),('domain','IoT'),('domain','Cloud'),
('platform','Linux'),('platform','RTOS'),('platform','Android'),
('framework','ROS'),('framework','TensorFlow'),('framework','Qt'),
('technology','Python'),('technology','C++'),('technology','Java'),('technology','Bash'),('technology','SQL'),('technology','Selenium'),('technology','Cypress'),('technology','Docker'),
('capability','Root Cause Analysis'),('capability','Combinatorial Testing'),('capability','State Transition Testing'),('capability','Risk-Based Testing'),('capability','System Diagnostics'),('capability','Performance Testing'),('capability','Security Testing'),('capability','Hardware Diagnostics'),
('regulation','FDA'),('regulation','HIPAA'),('regulation','IEC62304')
ON CONFLICT(name) DO NOTHING;
"

    _apply_migration "003" "
INSERT INTO classifiers (name, version, rule_hash, description) VALUES
('domain_classifier','1.0','sha256-abc123','Pattern-based domain detection'),
('tech_classifier','1.0','sha256-def456','Pattern-based technology detection'),
('capability_classifier','1.0','sha256-ghi789','Pattern-based capability detection'),
('industry_classifier','1.0','sha256-jkl012','Pattern-based industry detection')
ON CONFLICT(name, version) DO NOTHING;
"

    _apply_migration "004" "
INSERT INTO career_phases (company, role, years, context) VALUES
('Lexmark','Software Systems Tester','2003-2006','Printer firmware testing, memory leak detection, combinatorial testing, requirements-based testing, embedded systems, C, USB'),
('NCR','Software Tester','2017-2018','POS hardware-software integration, scanners, touch-panels, payment logic, combinatorial test design, race conditions'),
('InspireX','Senior QA Engineer','2025-Present','AMX programming, audio/video device APIs, AI services, Bash/Python automation, system logs, hardware-software state transitions'),
('Evo Tech','Senior QA Engineer','2024-2025','API testing, SQL data validation, end-to-end testing, root cause analysis, Selenium, Cypress'),
('23point5','QA Engineer','2023-2024','E-commerce testing, cart and payment flows, risk-based testing, Selenium, Python'),
('Accenture','Test Engineering Analyst','2019-2020','Functional and performance testing, Salesforce, telecom enterprise, automation, JMeter'),
('SAAD Hospital','IT Help Desk','2007-2012','Tier 1/2 support, proactive monitoring, preventive maintenance, incident reduction')
ON CONFLICT(company, role, years) DO NOTHING;
"

    _apply_migration "005" "
CREATE INDEX IF NOT EXISTS idx_obs_evidence ON observations(evidence_id);
CREATE INDEX IF NOT EXISTS idx_obs_classifier ON observations(classifier_id);
CREATE INDEX IF NOT EXISTS idx_res_observation ON resolutions(observation_id);
CREATE INDEX IF NOT EXISTS idx_res_concept ON resolutions(concept_id);
CREATE INDEX IF NOT EXISTS idx_evidence_subject ON evidence(subject_type, subject_id);
CREATE INDEX IF NOT EXISTS idx_jobs_company ON jobs(company_id);
CREATE INDEX IF NOT EXISTS idx_companies_name ON companies(name);
CREATE INDEX IF NOT EXISTS idx_taxonomy_name ON taxonomy(name);
CREATE INDEX IF NOT EXISTS idx_events_type_time ON events(event_type, timestamp);
"

    _apply_migration "006" "
CREATE VIEW IF NOT EXISTS company_knowledge AS
SELECT c.id AS company_id, c.name AS company_name, r.concept_id, t.name AS concept_name, t.concept_type,
       COUNT(DISTINCT o.id) AS observation_count, MAX(e.captured_at) AS last_seen,
       COUNT(DISTINCT o.classifier_id) AS classifier_count
FROM companies c
JOIN evidence e ON e.subject_type = 'company' AND e.subject_id = c.id
JOIN observations o ON o.evidence_id = e.id
JOIN resolutions r ON r.observation_id = o.id
JOIN taxonomy t ON t.id = r.concept_id
GROUP BY c.id, r.concept_id;

CREATE VIEW IF NOT EXISTS career_knowledge AS
SELECT cp.id AS phase_id, cp.company AS career_company, r.concept_id, t.name AS concept_name, t.concept_type,
       COUNT(DISTINCT o.id) AS observation_count, COUNT(DISTINCT o.classifier_id) AS classifier_count
FROM career_phases cp
JOIN evidence e ON e.subject_type = 'career_phase' AND e.subject_id = cp.id
JOIN observations o ON o.evidence_id = e.id
JOIN resolutions r ON r.observation_id = o.id
JOIN taxonomy t ON t.id = r.concept_id
GROUP BY cp.id, r.concept_id;
"

    _apply_migration "007" "
INSERT OR IGNORE INTO taxonomy (concept_type, name) VALUES
('domain','QA'),
('domain','Software Testing'),
('domain','Automation'),
('technology','API'),
('technology','Automation');"

    # ---- Caches + Career Import ----
    _cache_taxonomy
    _cache_classifiers

    if ! sqlite3 "$CIE_DB_PATH" "SELECT 1 FROM data_bootstrap WHERE key='career_imported';" | grep -q 1; then
        log "Importing career phases..."
        if sqlite3 "$CIE_DB_PATH" <<'EOFSQL'
BEGIN;
INSERT OR IGNORE INTO evidence (subject_type, subject_id, source_system, source_type, raw_text)
SELECT 'career_phase', id, 'manual', 'resume', context || ' ' || company || ' ' || role
FROM career_phases;
COMMIT;
EOFSQL
        then
            _classify_career_evidence_batch
            sqlite3 "$CIE_DB_PATH" "INSERT INTO data_bootstrap (key, value) VALUES ('career_imported', datetime('now'));"
        else
            log "ERROR: Failed to import career phases."
            exit 1
        fi
    fi

    log "Database ready."
}

# -----------------------------------------------------------------------------
# CLASSIFIER – Single-pass GAWK (unchanged)
# -----------------------------------------------------------------------------
_classify_text_awk() {
    local text="$1"
    gawk '
    BEGIN {
        regex[0] = "(embedded|firmware|driver|rtos|microcontroller|arm|spi|i2c|uart|can|bootloader)"; type[0] = "domain"; concept[0] = "Embedded"
        regex[1] = "(robot|robotic|motion control|autonomous|ros|computer vision|vision system|motor control|servo|actuator)"; type[1] = "domain"; concept[1] = "Robotics"
        regex[2] = "(firmware|driver|memory|register|bootloader)"; type[2] = "domain"; concept[2] = "Firmware"
        regex[3] = "(hardware integration|device api|system integration|hardware validation|hardware-software|hardware test|touch panel|scanner|printer|sensor)"; type[3] = "domain"; concept[3] = "Hardware-Integration"
        regex[4] = "(ai|machine learning|llm|computer vision|nlp|inference|model training|tensorflow|pytorch)"; type[4] = "domain"; concept[4] = "AI"
        regex[5] = "\\blinux\\b"; type[5] = "technology"; concept[5] = "Linux"
        regex[6] = "\\bpython\\b"; type[6] = "technology"; concept[6] = "Python"
        regex[7] = "\\bbash\\b"; type[7] = "technology"; concept[7] = "Bash"
        regex[8] = "\\bsql\\b"; type[8] = "technology"; concept[8] = "SQL"
        regex[9] = "\\bselenium\\b"; type[9] = "technology"; concept[9] = "Selenium"
        regex[10] = "\\bcypress\\b"; type[10] = "technology"; concept[10] = "Cypress"
        regex[11] = "\\bdocker\\b"; type[11] = "technology"; concept[11] = "Docker"
        regex[12] = "\\bc\\+\\+|cpp"; type[12] = "technology"; concept[12] = "C++"
        regex[13] = "\\bjava\\b"; type[13] = "technology"; concept[13] = "Java"
        regex[14] = "\\bros\\b"; type[14] = "technology"; concept[14] = "ROS"
        regex[15] = "(root cause analysis|root-cause|rca)"; type[15] = "capability"; concept[15] = "Root Cause Analysis"
        regex[16] = "(combinatorial testing|pairwise|pair-wise)"; type[16] = "capability"; concept[16] = "Combinatorial Testing"
        regex[17] = "(state transition|state-machine)"; type[17] = "capability"; concept[17] = "State Transition Testing"
        regex[18] = "(risk-based testing|risk based|risk-based)"; type[18] = "capability"; concept[18] = "Risk-Based Testing"
        regex[19] = "(diagnostics|system logs|log analysis)"; type[19] = "capability"; concept[19] = "System Diagnostics"
        regex[20] = "(performance testing|load testing|jmeter)"; type[20] = "capability"; concept[20] = "Performance Testing"
        regex[21] = "(security testing|penetration testing)"; type[21] = "capability"; concept[21] = "Security Testing"
        regex[22] = "(hardware diagnostics|hardware debug)"; type[22] = "capability"; concept[22] = "Hardware Diagnostics"
        regex[23] = "\\bpos\\b"; type[23] = "product"; concept[23] = "POS System"
        regex[24] = "(printer|printing)"; type[24] = "product"; concept[24] = "Printer"
        regex[25] = "(scanner|scanning)"; type[25] = "product"; concept[25] = "Scanner"
        regex[26] = "(payment|payments|payroll)"; type[26] = "product"; concept[26] = "Payment System"
        regex[27] = "(medical device|diagnostic|healthcare|clinical|radiology|patient)"; type[27] = "industry"; concept[27] = "Medical Devices"
        regex[28] = "(consumer electronics|appliance|gadget)"; type[28] = "industry"; concept[28] = "Consumer Electronics"
        regex[29] = "(industrial automation|manufacturing|factory|plc|scada)"; type[29] = "industry"; concept[29] = "Industrial Automation"
        regex[30] = "(semiconductor|chip|asic|fpga|silicon|wafer)"; type[30] = "industry"; concept[30] = "Semiconductor"
        regex[31] = "(payment|banking|financial|fintech|atm|wallet)"; type[31] = "industry"; concept[31] = "FinTech"
        regex[32] = "(enterprise|saas|erp|crm|salesforce|oracle|sap)"; type[32] = "industry"; concept[32] = "Enterprise Software"
        regex[33] = "\\bqa\\b"; type[33] = "domain"; concept[33] = "QA"
        regex[34] = "\\btest\\b"; type[34] = "domain"; concept[34] = "Software Testing"
        regex[35] = "\\bautomation\\b"; type[35] = "domain"; concept[35] = "Automation"
        regex[36] = "\\bapi\\b"; type[36] = "technology"; concept[36] = "API"
        total = 37
    }
    {
        delete seen
        txt = tolower($0)
        for (i = 0; i < total; i++) {
            if (match(txt, regex[i])) {
                key = type[i] "|" concept[i]
                if (!seen[key]) {
                    seen[key] = 1
                    print type[i] "|" concept[i]
                }
            }
        }
    }
    ' <<< "$text" 2>/dev/null
}

# -----------------------------------------------------------------------------
# BATCH CLASSIFIER FOR CAREER
# -----------------------------------------------------------------------------
_classify_career_evidence_batch() {
    local classifier_id
    classifier_id=$(_get_classifier_id "$CIE_CLASSIFIER_NAME" "$CIE_CLASSIFIER_VERSION")
    [[ -z "$classifier_id" ]] && return

    local sql_file
    sql_file=$(mktemp)

    sqlite3 "$CIE_DB_PATH" "SELECT id, raw_text FROM evidence WHERE subject_type='career_phase';" | while IFS='|' read -r eid raw; do
        local classes
        classes=$(_classify_text_awk "$raw")
        if [[ -n "$classes" ]]; then
            while IFS='|' read -r obs_type concept; do
                [[ -z "$concept" ]] && continue
                local concept_id
                concept_id=$(_get_concept_id "$concept")
                echo "INSERT INTO observations (evidence_id, classifier_id, observation_type, matched_text)" >> "$sql_file"
                echo "  VALUES ($eid, $classifier_id, '$obs_type', '$(sql_quote "$concept")')" >> "$sql_file"
                echo "  ON CONFLICT(evidence_id, classifier_id, observation_type, matched_text) DO NOTHING;" >> "$sql_file"

                if [[ -n "$concept_id" ]]; then
                    echo "INSERT INTO resolutions (observation_id, concept_id, resolver_version, taxonomy_version)" >> "$sql_file"
                    echo "  SELECT o.id, $concept_id, 'resolver_v1', 'taxonomy_v1'" >> "$sql_file"
                    echo "  FROM observations o" >> "$sql_file"
                    echo "  WHERE o.evidence_id = $eid AND o.classifier_id = $classifier_id" >> "$sql_file"
                    echo "    AND o.observation_type = '$obs_type' AND o.matched_text = '$(sql_quote "$concept")'" >> "$sql_file"
                    echo "  ON CONFLICT(observation_id, concept_id) DO NOTHING;" >> "$sql_file"
                else
                    echo "INSERT INTO unknown_observations (observation_id, matched_text, reason)" >> "$sql_file"
                    echo "  SELECT o.id, '$(sql_quote "$concept")', 'No matching taxonomy concept'" >> "$sql_file"
                    echo "  FROM observations o" >> "$sql_file"
                    echo "  WHERE o.evidence_id = $eid AND o.classifier_id = $classifier_id" >> "$sql_file"
                    echo "    AND o.observation_type = '$obs_type' AND o.matched_text = '$(sql_quote "$concept")'" >> "$sql_file"
                    echo "  ON CONFLICT(observation_id) DO UPDATE SET seen_count = seen_count + 1, last_seen = CURRENT_TIMESTAMP;" >> "$sql_file"
                    echo "INSERT INTO events (event_type, subject_type, subject_id, payload)" >> "$sql_file"
                    echo "  SELECT 'ObservationUnresolved', 'observation', o.id, json_object('payload_version', 1, 'matched_text', '$(sql_quote "$concept")', 'classifier', $classifier_id, 'taxonomy_version', '$(sql_quote "$CIE_CLASSIFIER_VERSION")')" >> "$sql_file"
                    echo "  FROM observations o" >> "$sql_file"
                    echo "  WHERE o.evidence_id = $eid AND o.classifier_id = $classifier_id" >> "$sql_file"
                    echo "    AND o.observation_type = '$obs_type' AND o.matched_text = '$(sql_quote "$concept")'" >> "$sql_file"
                    echo "    AND NOT EXISTS (SELECT 1 FROM events e2 WHERE e2.subject_type = 'observation' AND e2.subject_id = o.id AND e2.event_type = 'ObservationUnresolved');" >> "$sql_file"
                fi
            done <<< "$classes"
        fi
    done

    _execute_transaction "$sql_file" "career_import"
    rm -f "$sql_file"
}

# -----------------------------------------------------------------------------
# ACQUISITION – Using Pipe‑Delimited Scraper Output
# -----------------------------------------------------------------------------
_acquire_jobstreet() {
    local output_file="$1"
    > "$output_file"   # clear output file

    for query in "${QA_KEYWORDS[@]}"; do
        log "Fetching jobs for keyword: '$query'"
        local raw_output
        # Call the scraper without --json (default pipe-delimited output)
        raw_output=$(python3 "$CIE_SCRAPER" "$query" 2>/dev/null) || {
            log "WARNING: Scraper failed for '$query'"
            continue
        }

        # Process each line and convert to JSON (compact output)
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            # Split by '|'
            IFS='|' read -r id title company url <<< "$line"
            # Build JSON object using jq with -c for compact, single-line output
            jq -c -n \
                --arg id "$id" \
                --arg title "$title" \
                --arg company "$company" \
                --arg url "$url" \
                '{id: $id, title: $title, company: $company, url: $url, salary: null, location: "Philippines"}' \
                >> "$output_file"
        done <<< "$raw_output"
    done

    local total
    total=$(wc -l < "$output_file")
    log "Total jobs fetched across all keywords: $total"
}

# -----------------------------------------------------------------------------
# TRANSACTION EXECUTION
# -----------------------------------------------------------------------------
_execute_transaction() {
    local sql_file="$1"
    local job_id="$2"
    local attempt=1
    local max_attempts="$CIE_MAX_RETRIES"

    while [[ $attempt -le $max_attempts ]]; do
        local error_log
        error_log=$(mktemp)
        if sqlite3 "$CIE_DB_PATH" <<EOF 2> "$error_log"
BEGIN IMMEDIATE;
$(cat "$sql_file")
COMMIT;
EOF
        then
            rm -f "$error_log"
            return 0
        else
            local err_msg
            err_msg=$(cat "$error_log")
            if echo "$err_msg" | grep -qiE 'database is locked|database schema is locked|SQLITE_BUSY|SQLITE_LOCKED|SQLITE_IOERR_BLOCKED|IOERR_BLOCKED'; then
                log "Transient lock error (attempt $attempt/$max_attempts) for job $job_id: $err_msg"
                rm -f "$error_log"
                if [[ $attempt -lt $max_attempts ]]; then
                    local delay=$((1 << (attempt - 1)))
                    ((delay > 30)) && delay=30
                    local jitter=$((RANDOM % 3))
                    sleep "$((delay + jitter))"
                fi
                ((attempt++))
                continue
            else
                log "ERROR: Transaction failed for job $job_id (attempt $attempt): $err_msg"
                local failed_sql
                failed_sql="${CIE_LOG_DIR}/failed_transaction_${job_id}_$(date +%Y%m%d_%H%M%S).sql"
                cp "$sql_file" "$failed_sql"
                log "Failed SQL saved to $failed_sql"
                rm -f "$error_log"
                return 1
            fi
        fi
    done

    log "ERROR: Transaction failed for job $job_id after $max_attempts attempts (busy)."
    return 1
}

# -----------------------------------------------------------------------------
# JOB SQL BUILDING
# -----------------------------------------------------------------------------
_append_company_sql() {
    local company="$1"
    local sql_file="$2"
    cat <<EOF >> "$sql_file"
INSERT INTO companies (name, first_seen, last_seen)
VALUES ('$(sql_quote "$company")', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
ON CONFLICT(name) DO UPDATE SET last_seen = CURRENT_TIMESTAMP;
EOF
}

_append_evidence_sql() {
    local company="$1"
    local url="$2"
    local raw_text="$3"
    local sql_file="$4"
    cat <<EOF >> "$sql_file"
INSERT INTO evidence (subject_type, subject_id, source_system, source_type, source_url, raw_text)
SELECT 'company', c.id, 'JobStreet', 'job_description', '$(sql_quote "$url")', '$(sql_quote "$raw_text")'
FROM companies c
WHERE c.name = '$(sql_quote "$company")'
ON CONFLICT(subject_type, subject_id, source_url, raw_text) DO NOTHING;
EOF
}

_append_job_sql() {
    local job_id="$1"
    local company="$2"
    local url="$3"
    local sql_file="$4"
    cat <<EOF >> "$sql_file"
INSERT INTO jobs (id, evidence_id, company_id, posted_date)
SELECT '$(sql_quote "$job_id")', e.id, c.id, CURRENT_TIMESTAMP
FROM companies c, evidence e
WHERE c.name = '$(sql_quote "$company")'
  AND e.subject_type = 'company'
  AND e.subject_id = c.id
  AND e.source_url = '$(sql_quote "$url")'
  AND e.source_type = 'job_description'
ON CONFLICT(id) DO NOTHING;
EOF
}

_append_classification_results_sql() {
    local company="$1"
    local url="$2"
    local classifier_id="$3"
    local obs_type="$4"
    local concept="$5"
    local sql_file="$6"
    local concept_id
    concept_id=$(_get_concept_id "$concept")

    cat <<EOF >> "$sql_file"
INSERT INTO observations (evidence_id, classifier_id, observation_type, matched_text)
SELECT e.id, $classifier_id, '$obs_type', '$(sql_quote "$concept")'
FROM companies c, evidence e
WHERE c.name = '$(sql_quote "$company")'
  AND e.subject_type = 'company'
  AND e.subject_id = c.id
  AND e.source_url = '$(sql_quote "$url")'
  AND e.source_type = 'job_description'
ON CONFLICT(evidence_id, classifier_id, observation_type, matched_text) DO NOTHING;
EOF

    if [[ -n "$concept_id" ]]; then
        cat <<EOF >> "$sql_file"
INSERT INTO resolutions (observation_id, concept_id, resolver_version, taxonomy_version)
SELECT o.id, $concept_id, 'resolver_v1', 'taxonomy_v1'
FROM observations o
JOIN evidence e ON e.id = o.evidence_id
JOIN companies c ON c.id = e.subject_id
WHERE c.name = '$(sql_quote "$company")'
  AND e.source_url = '$(sql_quote "$url")'
  AND e.source_type = 'job_description'
  AND o.classifier_id = $classifier_id
  AND o.observation_type = '$obs_type'
  AND o.matched_text = '$(sql_quote "$concept")'
ON CONFLICT(observation_id, concept_id) DO NOTHING;
EOF
    else
        cat <<EOF >> "$sql_file"
INSERT INTO unknown_observations (observation_id, matched_text, reason)
SELECT o.id, '$(sql_quote "$concept")', 'No matching taxonomy concept'
FROM observations o
JOIN evidence e ON e.id = o.evidence_id
JOIN companies c ON c.id = e.subject_id
WHERE c.name = '$(sql_quote "$company")'
  AND e.source_url = '$(sql_quote "$url")'
  AND e.source_type = 'job_description'
  AND o.classifier_id = $classifier_id
  AND o.observation_type = '$obs_type'
  AND o.matched_text = '$(sql_quote "$concept")'
ON CONFLICT(observation_id) DO UPDATE SET seen_count = seen_count + 1, last_seen = CURRENT_TIMESTAMP;
EOF
        cat <<EOF >> "$sql_file"
INSERT INTO events (event_type, subject_type, subject_id, payload)
SELECT 'ObservationUnresolved', 'observation', o.id,
       json_object('payload_version', 1, 'matched_text', '$(sql_quote "$concept")', 'classifier', $classifier_id, 'taxonomy_version', '$(sql_quote "$CIE_CLASSIFIER_VERSION")')
FROM observations o
JOIN evidence e ON e.id = o.evidence_id
JOIN companies c ON c.id = e.subject_id
WHERE c.name = '$(sql_quote "$company")'
  AND e.source_url = '$(sql_quote "$url")'
  AND e.source_type = 'job_description'
  AND o.classifier_id = $classifier_id
  AND o.observation_type = '$obs_type'
  AND o.matched_text = '$(sql_quote "$concept")'
  AND NOT EXISTS (SELECT 1 FROM events e2
                  WHERE e2.subject_type = 'observation'
                    AND e2.subject_id = o.id
                    AND e2.event_type = 'ObservationUnresolved');
EOF
    fi
}

_append_job_event_sql() {
    local job_id="$1"
    local company="$2"
    local title="$3"
    local sql_file="$4"
    cat <<EOF >> "$sql_file"
INSERT INTO events (event_type, subject_type, subject_id, payload)
SELECT 'JobObserved', 'job', j.id,
       json_object('payload_version', 1, 'company', '$(sql_quote "$company")', 'title', '$(sql_quote "$title")')
FROM jobs j
WHERE j.id = '$(sql_quote "$job_id")'
  AND NOT EXISTS (SELECT 1 FROM events e2
                  WHERE e2.event_type = 'JobObserved'
                    AND e2.subject_type = 'job'
                    AND e2.subject_id = j.id);
EOF
}

# -----------------------------------------------------------------------------
# BUILD JOB SQL
# -----------------------------------------------------------------------------
_build_job_sql() {
    local job_json="$1"
    local title company url job_id salary location classifier_id raw_text classes

    local fields
    mapfile -t fields < <(
        jq -r '
            .title // "",
            .company // "",
            .url // "",
            .id // "",
            (.salary | tostring),
            .location // ""
        ' <<<"$job_json"
    )

    if [[ ${#fields[@]} -ne 6 ]]; then
        log "ERROR: jq extraction returned ${#fields[@]} fields, expected 6. Skipping job."
        return 1
    fi

    title="${fields[0]}"
    company="${fields[1]}"
    url="${fields[2]}"
    job_id="${fields[3]}"
    salary="${fields[4]}"
    location="${fields[5]}"

    [[ -z "$title" || -z "$company" ]] && return 1

    classifier_id=$(_get_classifier_id "$CIE_CLASSIFIER_NAME" "$CIE_CLASSIFIER_VERSION")
    [[ -z "$classifier_id" ]] && { log "ERROR: Classifier not found"; return 1; }

    raw_text="$title $company $location $salary"
    classes=$(_classify_text_awk "$raw_text")

    local sql_file
    sql_file=$(mktemp)

    _append_company_sql "$company" "$sql_file"
    _append_evidence_sql "$company" "$url" "$raw_text" "$sql_file"
    _append_job_sql "$job_id" "$company" "$url" "$sql_file"

    if [[ -n "$classes" ]]; then
        while IFS='|' read -r obs_type concept; do
            [[ -z "$concept" ]] && continue
            _append_classification_results_sql "$company" "$url" "$classifier_id" "$obs_type" "$concept" "$sql_file"
        done <<< "$classes"
    fi

    _append_job_event_sql "$job_id" "$company" "$title" "$sql_file"

    echo "$sql_file"
}

# -----------------------------------------------------------------------------
# PROCESS JOB
# -----------------------------------------------------------------------------
_process_job() {
    local job_json="$1"
    local sql_file
    sql_file=$(_build_job_sql "$job_json")
    if [[ -z "$sql_file" || ! -f "$sql_file" ]]; then
        log "ERROR: Failed to build SQL for job."
        return 1
    fi

    local job_id
    job_id=$(echo "$job_json" | jq -r '.id // "unknown"')
    if ! _execute_transaction "$sql_file" "$job_id"; then
        log "Failed to commit job $job_id after retries."
        sqlite3 "$CIE_DB_PATH" "INSERT INTO events (event_type, subject_type, subject_id, payload) VALUES ('JobFailed', 'job', '$(sql_quote "$job_id")', json_object('payload_version', 1, 'error', 'transaction failed after retries'));" 2>/dev/null || log "WARNING: Could not log JobFailed event."
        rm -f "$sql_file"
        return 1
    fi

    rm -f "$sql_file"
    return 0
}

# -----------------------------------------------------------------------------
# QUERY
# -----------------------------------------------------------------------------
_query_recommendations() {
    local cutoff="$1"
    sqlite3 "$CIE_DB_PATH" <<EOF
WITH recent_jobs AS (SELECT DISTINCT company_id FROM jobs WHERE seen_date > '$cutoff'),
company_concepts AS (
    SELECT c.id AS company_id, c.name AS company_name, r.concept_id,
           MAX(r.resolved_at) AS latest_resolution,
           COUNT(DISTINCT o.id) AS observation_count,
           COUNT(DISTINCT o.classifier_id) AS classifier_count,
           MAX(e.captured_at) AS last_evidence
    FROM companies c
    JOIN recent_jobs rj ON rj.company_id = c.id
    JOIN evidence e ON e.subject_type = 'company' AND e.subject_id = c.id
    JOIN observations o ON o.evidence_id = e.id
    JOIN resolutions r ON r.observation_id = o.id
    GROUP BY c.id, r.concept_id
),
career_concepts AS (SELECT concept_id FROM career_knowledge),
shared AS (
    SELECT cc.company_id, cc.company_name,
           COUNT(DISTINCT cc.concept_id) AS shared_count,
           MAX(cc.last_evidence) AS most_recent,
           SUM(cc.observation_count) AS total_evidence,
           SUM(cc.classifier_count) AS total_classifiers
    FROM company_concepts cc
    JOIN career_concepts ca ON ca.concept_id = cc.concept_id
    GROUP BY cc.company_id, cc.company_name
)
SELECT company_id, company_name, shared_count, most_recent, total_evidence, total_classifiers
FROM shared
ORDER BY shared_count DESC, most_recent DESC, total_classifiers DESC
LIMIT ${CIE_MAX_RECOMMENDATIONS};
EOF
}

# -----------------------------------------------------------------------------
# NOTIFY
# -----------------------------------------------------------------------------
_notify_email() {
    local recommendations="$1"
    [[ -z "$recommendations" ]] && { log "No recommendations."; return 0; }

    local count
    count=$(echo "$recommendations" | wc -l)
    local subject="Career Intelligence: $count matching companies with new QA roles"

    local body
    body=$(mktemp)
    {
        printf 'To: %s\n' "$CIE_EMAIL_TO"
        printf 'Subject: %s\n' "$subject"
        printf 'Content-Type: text/plain; charset=UTF-8\n\n'
        printf 'Hi Claive,\n\n'
        printf 'Career Intelligence Engine found %d companies with new QA opportunities.\n\n' "$count"
        printf 'Ranked by shared concepts, recency, and classifier agreement.\n\n'
    } >> "$body"

    echo "$recommendations" | while IFS='|' read -r _ name shared most_recent evidence classifiers; do
        local encoded_name
        encoded_name=$(jq -rn --arg s "$name" '$s|@uri')
        printf '---------------------------------------------------------------------\n' >> "$body"
        printf 'Company: %s\n' "$name" >> "$body"
        printf '   Shared concepts: %d\n' "$shared" >> "$body"
        printf '   Evidence count: %d\n' "$evidence" >> "$body"
        printf '   Last seen: %s\n' "$most_recent" >> "$body"
        printf '   Classifier agreement: %d classifiers\n' "$classifiers" >> "$body"
        echo "   https://ph.jobstreet.com/jobs?keywords=$encoded_name" >> "$body"
    done

    printf '\n---\nSource: JobStreet Philippines\n' >> "$body"
    printf 'Apply quickly – positions may close soon.\n' >> "$body"
    printf 'Generated: %s\n' "$(date)" >> "$body"

    if msmtp -a "$CIE_SMTP_ACCOUNT" "$CIE_EMAIL_TO" < "$body"; then
        log "Email sent."
        sqlite3 "$CIE_DB_PATH" "INSERT INTO events (event_type, subject_type, subject_id, payload) VALUES ('RecommendationDelivered', 'system', '0', json_object('payload_version', 1, 'count', $count));"
    else
        log "Failed to send email."
        sqlite3 "$CIE_DB_PATH" "INSERT INTO events (event_type, subject_type, subject_id, payload) VALUES ('NotificationFailed', 'system', '0', json_object('payload_version', 1, 'error', 'msmtp failed'));"
    fi
    rm -f "$body"
}

# -----------------------------------------------------------------------------
# LOG ROTATION & MAINTENANCE
# -----------------------------------------------------------------------------
_rotate_logs() {
    find "$CIE_LOG_DIR" -name "cie_*.log" -type f -mtime +"$CIE_LOG_RETENTION_DAYS" -delete 2>/dev/null || true
    find "$CIE_LOG_DIR" -name "cie_search.jsonl" -type f -mtime +"$CIE_LOG_RETENTION_DAYS" -delete 2>/dev/null || true
}

_maintenance() {
    log "Running maintenance..."

    local sql_file
    sql_file=$(mktemp)
    cat <<EOF > "$sql_file"
DELETE FROM jobs WHERE seen_date < datetime('now', '-${CIE_RETENTION_DAYS} days');
DELETE FROM events WHERE timestamp < datetime('now', '-${CIE_RETENTION_DAYS} days');
EOF

    _execute_transaction "$sql_file" "maintenance"
    rm -f "$sql_file"

    local db_size
    db_size=$(stat -c%s "$CIE_DB_PATH" 2>/dev/null || echo 0)
    if [[ "$db_size" -gt 104857600 ]]; then
        log "VACUUMING database..."
        sqlite3 "$CIE_DB_PATH" "VACUUM;"
    fi

    log "Checkpointing WAL..."
    sqlite3 "$CIE_DB_PATH" "PRAGMA wal_checkpoint(TRUNCATE);"

    local unknowns
    unknowns=$(sqlite3 "$CIE_DB_PATH" "SELECT matched_text, COUNT(*) FROM unknown_observations GROUP BY matched_text ORDER BY COUNT(*) DESC LIMIT 10;")
    if [[ -n "$unknowns" ]]; then
        log "Unknown observations (consider adding to taxonomy):"
        echo "$unknowns" | while IFS='|' read -r text count; do
            log "   '$text' (seen $count times)"
        done
    fi

    sqlite3 "$CIE_DB_PATH" "PRAGMA optimize;"
    _rotate_logs
    sqlite3 "$CIE_DB_PATH" "INSERT OR REPLACE INTO maintenance_state (key, value) VALUES ('last_maintenance', datetime('now'));"
    log "Maintenance complete."
}

# -----------------------------------------------------------------------------
# MAIN CYCLE
# -----------------------------------------------------------------------------
_main_cycle() {
    log "Starting Career Intelligence Engine v12.8"

    _acquire_lock || exit 1

    _db_init

    local jobstream
    jobstream=$(mktemp)

    _acquire_jobstreet "$jobstream"

    local job_count=0
    while IFS= read -r job_json; do
        [[ -z "$job_json" ]] && continue
        if _process_job "$job_json"; then
            ((job_count++))
        fi
    done < "$jobstream"
    rm -f "$jobstream"

    log "Processed $job_count jobs."

    local cutoff
    cutoff=$(date -d "${CIE_CUTOFF_MINUTES} minutes ago" '+%Y-%m-%d %H:%M:%S')
    local recommendations
    recommendations=$(_query_recommendations "$cutoff")
    if [[ -n "$recommendations" ]]; then
        _notify_email "$recommendations"
    else
        log "No new recommendations."
    fi

    local last_maintenance
    last_maintenance=$(sqlite3 "$CIE_DB_PATH" "SELECT value FROM maintenance_state WHERE key='last_maintenance';" 2>/dev/null || echo "")
    if [[ -z "$last_maintenance" ]]; then
        _maintenance
    else
        local last_epoch
        last_epoch=$(date -d "$last_maintenance" +%s 2>/dev/null || echo 0)
        if [[ $(( ( $(date +%s) - last_epoch ) / 86400 )) -gt 7 ]]; then
            _maintenance
        fi
    fi

    _release_lock
    log "Cycle complete"
}

# -----------------------------------------------------------------------------
# ENTRY
# -----------------------------------------------------------------------------
if [[ "${1:-}" == "--once" ]]; then
    _main_cycle
else
    while true; do
        _main_cycle
        sleep $(( (RANDOM % 21) + 55 ))m
    done
fi
