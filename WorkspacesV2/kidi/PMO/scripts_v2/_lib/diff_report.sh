#!/usr/bin/env bash
# =============================================================================
#  _lib/diff_report.sh  —  baseline vs 업그레이드 후 비교 리포트
#  사용: bash _lib/diff_report.sh <baseline_dir> <compare_dir> <label>
#        예) bash _lib/diff_report.sh baseline/data cp_19.28/data 19.28
# =============================================================================

BASELINE_DIR="${1}"
COMPARE_DIR="${2}"
LABEL="${3:-unknown}"
REPORT_FILE="${COMPARE_DIR}/diff_report_${LABEL}_$(date '+%Y%m%d_%H%M%S').txt"

# ── 입력 검증 ─────────────────────────────────────────────────────────────
if [ ! -d "${BASELINE_DIR}" ] || [ ! -d "${COMPARE_DIR}" ]; then
  echo "ERROR: 디렉토리를 찾을 수 없습니다."
  echo "  baseline : ${BASELINE_DIR}"
  echo "  compare  : ${COMPARE_DIR}"
  exit 1
fi

BASELINE_SNAP=$(ls "${BASELINE_DIR}"/snapshot_*.txt 2>/dev/null | sort | tail -1)
COMPARE_SNAP=$(ls  "${COMPARE_DIR}"/snapshot_*.txt  2>/dev/null | sort | tail -1)
BASELINE_BLK=$(ls  "${BASELINE_DIR}"/blocks_*.txt   2>/dev/null | sort | tail -1)
COMPARE_BLK=$(ls   "${COMPARE_DIR}"/blocks_*.txt    2>/dev/null | sort | tail -1)

if [ -z "${BASELINE_SNAP}" ] || [ -z "${COMPARE_SNAP}" ]; then
  echo "ERROR: snapshot 파일이 없습니다."
  echo "  baseline : ${BASELINE_SNAP:-없음}"
  echo "  compare  : ${COMPARE_SNAP:-없음}"
  exit 1
fi

# ── 리포트 생성 ───────────────────────────────────────────────────────────
{
echo "================================================================"
echo "  ODA 이미지 업그레이드 검증 리포트"
echo "  비교 버전 : ${LABEL}"
echo "  생성 시각 : $(date '+%Y-%m-%d %H:%M:%S')"
echo "  BASELINE  : ${BASELINE_SNAP}"
echo "  COMPARE   : ${COMPARE_SNAP}"
echo "================================================================"

# ── 1. 행수 비교 ──────────────────────────────────────────────────────────
echo ""
echo "────────────────────────────────────────────────────────────────"
echo "  [1] 행수 비교"
echo "────────────────────────────────────────────────────────────────"
BASE_ROW=$(grep '\[ROW\] total_count=' "${BASELINE_SNAP}" | cut -d= -f2)
CMP_ROW=$( grep '\[ROW\] total_count=' "${COMPARE_SNAP}"  | cut -d= -f2)
echo "  baseline  : ${BASE_ROW} 행"
echo "  ${LABEL}  : ${CMP_ROW} 행"
if [ "${BASE_ROW}" = "${CMP_ROW}" ]; then
  echo "  결과      : ✓ 일치"
else
  echo "  결과      : ✗ 불일치!  차이=$(( CMP_ROW - BASE_ROW ))"
fi

# ── 2. 세그먼트 크기 비교 ─────────────────────────────────────────────────
echo ""
echo "────────────────────────────────────────────────────────────────"
echo "  [2] 세그먼트 크기 비교"
echo "────────────────────────────────────────────────────────────────"
printf "  %-50s  %-15s  %-15s  %s\n" "SEGMENT" "BASELINE" "${LABEL}" "상태"
while IFS= read -r line; do
  KEY=$(echo "${line}" | sed 's/\[SEG\] //' | cut -d= -f1)
  BASE_VAL=$(grep "\[SEG\] ${KEY}=" "${BASELINE_SNAP}" | cut -d= -f2)
  CMP_VAL=$( grep "\[SEG\] ${KEY}=" "${COMPARE_SNAP}"  | cut -d= -f2)
  if [ "${BASE_VAL}" = "${CMP_VAL}" ]; then
    STATUS="✓ 일치"
  else
    STATUS="✗ 변경"
  fi
  printf "  %-50s  %-15s  %-15s  %s\n" "${KEY}" "${BASE_VAL}" "${CMP_VAL}" "${STATUS}"
done < <(grep '^\[SEG\]' "${BASELINE_SNAP}")

# ── 3. 인덱스 상태 비교 ───────────────────────────────────────────────────
echo ""
echo "────────────────────────────────────────────────────────────────"
echo "  [3] 인덱스 상태 비교"
echo "────────────────────────────────────────────────────────────────"
while IFS= read -r line; do
  KEY=$(echo "${line}" | sed 's/\[IDX\] //' | cut -d= -f1)
  BASE_VAL=$(grep "\[IDX\] ${KEY}=" "${BASELINE_SNAP}" | cut -d= -f2-)
  CMP_VAL=$( grep "\[IDX\] ${KEY}=" "${COMPARE_SNAP}"  | cut -d= -f2-)
  if [ "${BASE_VAL}" = "${CMP_VAL}" ]; then
    echo "  ✓ ${KEY}=${CMP_VAL}"
  else
    echo "  ✗ ${KEY}: baseline=${BASE_VAL}  →  ${LABEL}=${CMP_VAL}"
  fi
done < <(grep '^\[IDX\]' "${BASELINE_SNAP}")

# ── 4. 블록 손상 비교 ─────────────────────────────────────────────────────
echo ""
echo "────────────────────────────────────────────────────────────────"
echo "  [4] 블록 손상 비교"
echo "────────────────────────────────────────────────────────────────"
BASE_BLK_CNT=$(grep '\[BLOCK\] corruption_count=' "${BASELINE_SNAP}" | cut -d= -f2)
CMP_BLK_CNT=$( grep '\[BLOCK\] corruption_count=' "${COMPARE_SNAP}"  | cut -d= -f2)
echo "  baseline  : 손상 ${BASE_BLK_CNT:-0} 블록"
echo "  ${LABEL}  : 손상 ${CMP_BLK_CNT:-0} 블록"

# RMAN validate 결과 비교
if [ -n "${BASELINE_BLK}" ] && [ -n "${COMPARE_BLK}" ]; then
  RMAN_DIFF=$(diff "${BASELINE_BLK}" "${COMPARE_BLK}" | grep -c '^[<>]' || true)
  echo "  RMAN 로그 차이 라인 수: ${RMAN_DIFF}"
  if [ "${RMAN_DIFF}" -eq 0 ]; then
    echo "  결과: ✓ RMAN 결과 동일"
  else
    echo "  결과: ★ RMAN 결과 차이 있음 — 아래 상세 확인"
    diff "${BASELINE_BLK}" "${COMPARE_BLK}" | head -40
  fi
fi

# ── 5. 데이터 지문 비교 ───────────────────────────────────────────────────
echo ""
echo "────────────────────────────────────────────────────────────────"
echo "  [5] 데이터 지문 비교 (ORA_HASH 상위 100만 행 샘플)"
echo "────────────────────────────────────────────────────────────────"
BASE_HASH=$(grep '\[HASH\] rowid_ora_hash_sum=' "${BASELINE_SNAP}" | cut -d= -f2)
CMP_HASH=$( grep '\[HASH\] rowid_ora_hash_sum=' "${COMPARE_SNAP}"  | cut -d= -f2)
echo "  baseline  : ${BASE_HASH}"
echo "  ${LABEL}  : ${CMP_HASH}"
if [ "${BASE_HASH}" = "${CMP_HASH}" ]; then
  echo "  결과      : ✓ 샘플 지문 일치"
else
  echo "  결과      : ✗ 샘플 지문 불일치 — 데이터 변동 가능성 확인 필요"
fi

# ── 6. 전체 판정 ──────────────────────────────────────────────────────────
echo ""
echo "================================================================"
ISSUES=0
[ "${BASE_ROW}" != "${CMP_ROW}" ] && ISSUES=$((ISSUES+1))
[ "${BASE_HASH}" != "${CMP_HASH}" ] && ISSUES=$((ISSUES+1))
[ "${CMP_BLK_CNT:-0}" != "0" ] && ISSUES=$((ISSUES+1))

if [ "${ISSUES}" -eq 0 ]; then
  echo "  ★ 최종 판정: PASS — 업그레이드 후 데이터 이상 없음 ★"
else
  echo "  ★ 최종 판정: FAIL — ${ISSUES}개 항목 이상. 상세 확인 필요 ★"
fi
echo "  리포트 저장: ${REPORT_FILE}"
echo "================================================================"
} | tee "${REPORT_FILE}"
