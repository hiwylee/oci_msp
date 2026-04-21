#!/usr/bin/env bash
# =============================================================================
#  baseline/run_baseline.sh  —  ODA 업그레이드 전 기준값 수집
#  실행: bash baseline/run_baseline.sh
#  출력: baseline/data/snapshot_YYYYMMDD_HH.txt
#        baseline/data/blocks_YYYYMMDD_HH.txt
#        baseline/data/BASELINE_VERSION.txt
# =============================================================================
#  ★ ODA 이미지 업그레이드 전 반드시 실행하세요
#  ★ baseline/data/ 파일은 업그레이드 완료 후까지 보존하세요
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/00_config.sh"

DATA_DIR="${SCRIPT_DIR}/baseline/data"
mkdir -p "${DATA_DIR}"

TS=$(date '+%Y%m%d_%H%M%S')
SNAP_FILE="${DATA_DIR}/snapshot_${TS}.txt"
BLK_FILE="${DATA_DIR}/blocks_${TS}.txt"
VER_FILE="${DATA_DIR}/BASELINE_VERSION.txt"

echo "================================================================"
echo " ODA 업그레이드 전 BASELINE 수집"
echo " $(date '+%Y-%m-%d %H:%M:%S')"
echo " 출력 디렉토리: ${DATA_DIR}"
echo "================================================================"

# ── Step 1: DB 버전 / ODA 이미지 버전 기록 ───────────────────────────────
echo ""
echo "[1/3] DB 및 ODA 버전 기록 → ${VER_FILE}"

{
  echo "=== BASELINE VERSION INFO ==="
  echo "captured_at=$(date '+%Y-%m-%d %H:%M:%S')"

  sqlplus -S "/ as sysdba" <<'EOF'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT 'db_version='    || version      FROM v$instance;
SELECT 'db_name='       || name         FROM v$database;
SELECT 'host_name='     || host_name    FROM v$instance;
SELECT 'startup_time='  || TO_CHAR(startup_time,'YYYY-MM-DD HH24:MI:SS') FROM v$instance;
EOF

  # ODA 이미지 버전 (odacli 명령 사용 가능 환경)
  if command -v odacli &>/dev/null; then
    echo "=== ODA IMAGE VERSION ==="
    odacli describe-component 2>/dev/null | grep -E 'OAK|GI|DB' | head -10
  else
    echo "oda_image_version=수동확인필요(odacli describe-component)"
  fi
} > "${VER_FILE}"

cat "${VER_FILE}"

# ── Step 2: 데이터 스냅샷 수집 ───────────────────────────────────────────
echo ""
echo "[2/3] 데이터 스냅샷 수집 → ${SNAP_FILE}"
echo "      (행수·세그먼트·해시 — 수 분 소요 가능)"

sqlplus -S "/ as sysdba" <<SQLEOF > "${SNAP_FILE}"
@${SCRIPT_DIR}/_lib/collect.sql
SQLEOF

echo "      완료. 행수 확인:"
grep '\[ROW\] total_count' "${SNAP_FILE}"
grep '\[SEG\] total_all'   "${SNAP_FILE}"

# ── Step 3: RMAN 블록 검증 ───────────────────────────────────────────────
echo ""
echo "[3/3] RMAN 블록 무결성 검사 → ${BLK_FILE}"
echo "      (100GB+ LOB 환경: 10~30분 소요 가능 — 백그라운드 실행)"

bash "${SCRIPT_DIR}/_lib/rman_validate.sh" "${BLK_FILE}"

# ── 완료 요약 ─────────────────────────────────────────────────────────────
echo ""
echo "================================================================"
echo " BASELINE 수집 완료: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""
echo " 저장 파일:"
ls -lh "${DATA_DIR}/"
echo ""
echo " ★ 다음 단계:"
echo "   - 이 파일들을 안전한 위치에 보관하세요"
echo "   - ODA 19.28 업그레이드 후: bash cp_19.28/run_compare.sh"
echo "   - ODA 19.30 업그레이드 후: bash cp_19.30/run_compare.sh"
echo "================================================================"
