#!/usr/bin/env bash
# =============================================================================
#  cp_19.28/run_compare.sh  —  ODA 19.28 업그레이드 후 데이터 검증
#  실행: bash cp_19.28/run_compare.sh
#  전제: baseline/run_baseline.sh 가 먼저 실행되어 baseline/data/ 존재
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/00_config.sh"

ODA_VERSION="19.28"
DATA_DIR="${SCRIPT_DIR}/cp_19.28/data"
BASELINE_DIR="${SCRIPT_DIR}/baseline/data"
mkdir -p "${DATA_DIR}"

TS=$(date '+%Y%m%d_%H%M%S')
SNAP_FILE="${DATA_DIR}/snapshot_${TS}.txt"
BLK_FILE="${DATA_DIR}/blocks_${TS}.txt"

echo "================================================================"
echo " ODA ${ODA_VERSION} 업그레이드 후 데이터 검증"
echo " $(date '+%Y-%m-%d %H:%M:%S')"
echo "================================================================"

# baseline 존재 확인
if [ -z "$(ls "${BASELINE_DIR}"/snapshot_*.txt 2>/dev/null)" ]; then
  echo "ERROR: baseline/data/snapshot_*.txt 가 없습니다."
  echo "       먼저 baseline/run_baseline.sh 를 실행하세요."
  exit 1
fi

echo ""
echo " 사용할 BASELINE:"
ls -lh "${BASELINE_DIR}"/snapshot_*.txt | tail -1

# ── Step 1: 현재 DB 버전 확인 ────────────────────────────────────────────
echo ""
echo "[1/3] 현재 DB 버전 확인"
sqlplus -S "/ as sysdba" <<'EOF'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT 'db_version=' || version   FROM v$instance;
SELECT 'db_name='    || name      FROM v$database;
EOF

# ── Step 2: 데이터 스냅샷 수집 ───────────────────────────────────────────
echo ""
echo "[2/3] 데이터 스냅샷 수집 → ${SNAP_FILE}"

sqlplus -S "/ as sysdba" <<SQLEOF > "${SNAP_FILE}"
@${SCRIPT_DIR}/_lib/collect.sql
SQLEOF

echo "      완료. 행수 확인:"
grep '\[ROW\] total_count' "${SNAP_FILE}"
grep '\[SEG\] total_all'   "${SNAP_FILE}"

# ── Step 3: RMAN 블록 검증 ───────────────────────────────────────────────
echo ""
echo "[3/3] RMAN 블록 무결성 검사 → ${BLK_FILE}"

bash "${SCRIPT_DIR}/_lib/rman_validate.sh" "${BLK_FILE}"

# ── Step 4: baseline 과 비교 리포트 생성 ─────────────────────────────────
echo ""
echo "================================================================"
echo " BASELINE vs ODA ${ODA_VERSION} 비교 리포트"
echo "================================================================"

bash "${SCRIPT_DIR}/_lib/diff_report.sh" \
  "${BASELINE_DIR}" \
  "${DATA_DIR}" \
  "${ODA_VERSION}"
