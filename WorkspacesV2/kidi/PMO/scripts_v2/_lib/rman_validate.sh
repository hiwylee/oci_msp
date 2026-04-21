#!/usr/bin/env bash
# =============================================================================
#  _lib/rman_validate.sh  —  RMAN 블록 무결성 검증 (공통 사용)
#  호출: source _lib/rman_validate.sh  또는  bash _lib/rman_validate.sh <출력파일>
# =============================================================================

OUTFILE="${1:-/tmp/rman_validate_$(date '+%Y%m%d_%H%M%S').txt}"

echo "[$(date '+%H:%M:%S')] RMAN VALIDATE 시작 → ${OUTFILE}"

rman target / <<RMANEOF | tee "${OUTFILE}"
-- 물리적·논리적 블록 손상 검사
-- CHECK LOGICAL: 논리적 블록 체크 (데이터 일관성)
VALIDATE TABLE AOSORA.TBAIIMGLOG01M
  INCLUDING INDEXES
  CHECK LOGICAL;

-- 결과는 v\$database_block_corruption에 기록됨
-- 손상 없으면 "validated with no errors" 메시지 출력
RMANEOF

echo "[$(date '+%H:%M:%S')] RMAN VALIDATE 완료"

# 손상 블록 수 즉시 확인
CORRUPT_COUNT=$(sqlplus -S "/ as sysdba" <<'EOF'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT COUNT(*) FROM v$database_block_corruption;
EOF
)
echo "[BLOCK_CHECK] corruption_count=${CORRUPT_COUNT}" | tee -a "${OUTFILE}"

if [ "${CORRUPT_COUNT}" -gt 0 ] 2>/dev/null; then
  echo "[BLOCK_CHECK] ★ 손상 블록 발견! 상세 확인 필요" | tee -a "${OUTFILE}"
  sqlplus -S "/ as sysdba" <<'EOF' | tee -a "${OUTFILE}"
SET LINESIZE 120 PAGESIZE 50
SELECT file#, block#, blocks, corruption_type, con_id
FROM   v$database_block_corruption
ORDER  BY file#, block#;
EOF
else
  echo "[BLOCK_CHECK] 블록 손상 없음 (정상)" | tee -a "${OUTFILE}"
fi
