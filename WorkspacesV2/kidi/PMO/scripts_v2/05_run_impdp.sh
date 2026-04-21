#!/usr/bin/env bash
# =============================================================================
#  05_run_impdp.sh  —  impdp 실행
#  DB   : NAOSPOC  |  Table: TBAIIMGLOG01M  |  ODA odb8 (8 OCPU)
#  덤프 : 2023×3 + 2024×10  →  같은 테이블에 APPEND
#
#  실행 : nohup ./05_run_impdp.sh > /tmp/impdp_master.log 2>&1 &
#         tail -f /tmp/impdp_master.log
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00_config.sh"

mkdir -p "${IMPDP_LOG_DIR}"

echo "================================================================"
echo " NAOSPOC impdp 시작: $(date '+%Y-%m-%d %H:%M:%S')"
echo " 테이블  : AOSORA.TBAIIMGLOG01M"
echo " 덤프경로: ${DUMP_BASE}"
echo " 병렬수  : ${PARALLEL_DEGREE}  (ODA odb8 / 8OCPU)"
echo "================================================================"

# ── Force Logging 확인 (NOLOGGING 효과 여부) ─────────────────────────────
echo ""
echo "[사전확인] Force Logging 상태"
sqlplus -S "${DBA_CONNECT}" <<'EOF'
SET HEADING OFF FEEDBACK OFF
SELECT 'ForceLogging=' || force_logging FROM v$database;
EOF

# =============================================================================
#  impdp 파라미터 설명
# -----------------------------------------------------------------------------
#  PARALLEL=4             ODA odb8 적정값 (서비스 부하 감안, 최대 8)
#  TRANSFORM=             DISABLE_ARCHIVE_LOGGING:Y
#                         → 테이블·인덱스·LOB 모두 NOLOGGING 적용 (아카이브 절감)
#                         ※ Force Logging=YES 이면 이 옵션은 무효
#  TABLE_EXISTS_ACTION=   APPEND : 2023 로딩 후 2024를 같은 테이블에 추가
#  TABLES=                특정 테이블만 임포트 (스키마 전체 대신)
#  REMAP_TABLESPACE=      기존 TBS → IMGLOG_DATA_TBS/IMGLOG_LOB_TBS 로 재매핑
#  EXCLUDE=STATISTICS     로딩 후 DBMS_STATS로 별도 수집 (정확도 향상)
#  CONTENT=DATA_ONLY      2024 APPEND 시: 테이블 구조는 이미 있으므로 데이터만
#  LOGTIME=ALL            각 단계 타임스탬프 기록
#  METRICS=Y              처리량(rows/sec, bytes/sec) 로그 기록
# =============================================================================

# ── impdp 실행 함수 ───────────────────────────────────────────────────────
run_impdp() {
  local LABEL=$1          # "2023" 또는 "2024"
  local DUMPFILES=$2      # 쉼표 구분 파일 목록
  local CONTENT_OPT=$3    # "" (첫 실행) 또는 "CONTENT=DATA_ONLY" (APPEND)

  local TS=$(date '+%Y%m%d_%H%M%S')
  local LOGFILE="${IMPDP_LOG_DIR}/impdp_${LABEL}_${TS}.log"

  echo ""
  echo "----------------------------------------------------------------"
  echo " [${LABEL}] 시작: $(date '+%Y-%m-%d %H:%M:%S')"
  echo " 파일   : ${DUMPFILES}"
  echo " 로그   : ${LOGFILE}"
  echo "----------------------------------------------------------------"

  impdp "${DBA_CONNECT}" \
    DIRECTORY="${ORA_DIR_NAME}" \
    DUMPFILE="${DUMPFILES}" \
    LOGFILE="${ORA_LOG_DIR}:impdp_${LABEL}_${TS}.log" \
    TABLES="${SRC_SCHEMA}.${SRC_TABLE}" \
    REMAP_SCHEMA="${REMAP_SCHEMA}" \
    REMAP_TABLESPACE="USERS:IMGLOG_DATA_TBS,SYSTEM:IMGLOG_DATA_TBS,SYSAUX:IMGLOG_DATA_TBS" \
    PARALLEL="${PARALLEL_DEGREE}" \
    TRANSFORM=DISABLE_ARCHIVE_LOGGING:Y \
    TABLE_EXISTS_ACTION=APPEND \
    ${CONTENT_OPT} \
    EXCLUDE=STATISTICS \
    DATA_OPTIONS=SKIP_CONSTRAINT_ERRORS \
    LOGTIME=ALL \
    METRICS=Y \
    2>&1 | tee -a "${LOGFILE}"

  local RC=${PIPESTATUS[0]}
  echo ""
  if [ $RC -eq 0 ]; then
    echo " [${LABEL}] 완료: $(date '+%Y-%m-%d %H:%M:%S') — 성공"
  else
    echo " [${LABEL}] exit=${RC}  → 로그 확인: ${LOGFILE}"
    echo " ORA-39154(rows skipped)는 무시 가능. 다른 ORA- 는 확인 필요."
    echo " 계속하려면 Enter / 중단 Ctrl+C"
    read -r
  fi
}

# =============================================================================
# STEP A : 2023년 덤프 3개  (테이블 DDL + 데이터 함께 임포트)
# =============================================================================
DUMPLIST_2023=$(IFS=,; echo "${DUMP_FILES_2023[*]}")

echo ""
echo "================================================================"
echo " STEP A: 2023년 임포트 (${#DUMP_FILES_2023[@]}개)"
echo "================================================================"

run_impdp "2023" "${DUMPLIST_2023}" ""

# =============================================================================
# STEP B : 2024년 덤프 10개  (테이블 이미 존재 → DATA_ONLY + APPEND)
# =============================================================================
DUMPLIST_2024=$(IFS=,; echo "${DUMP_FILES_2024[*]}")

echo ""
echo "================================================================"
echo " STEP B: 2024년 임포트 (${#DUMP_FILES_2024[@]}개) — DATA_ONLY APPEND"
echo "================================================================"

run_impdp "2024" "${DUMPLIST_2024}" "CONTENT=DATA_ONLY"

# =============================================================================
# STEP C : 통계 재수집
# =============================================================================
echo ""
echo "================================================================"
echo " STEP C: AOSORA.TBAIIMGLOG01M 통계 재수집"
echo "================================================================"

sqlplus -S "${DBA_CONNECT}" <<SQLEOF
SET SERVEROUTPUT ON SIZE UNLIMITED
BEGIN
  DBMS_STATS.GATHER_TABLE_STATS(
    ownname     => 'AOSORA',
    tabname     => 'TBAIIMGLOG01M',
    cascade     => TRUE,
    degree      => ${PARALLEL_DEGREE},
    method_opt  => 'FOR ALL COLUMNS SIZE AUTO',
    granularity => 'ALL',
    no_invalidate => FALSE
  );
  DBMS_OUTPUT.PUT_LINE('통계 수집 완료: ' || TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS'));
END;
/
SQLEOF

echo ""
echo "================================================================"
echo " 전체 완료: $(date '+%Y-%m-%d %H:%M:%S')"
echo " 검증: sqlplus / as sysdba @06_verify.sql"
echo "================================================================"
