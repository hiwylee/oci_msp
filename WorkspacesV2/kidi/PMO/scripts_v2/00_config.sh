#!/usr/bin/env bash
# =============================================================================
#  00_config.sh  —  공통 설정 파일  (여기만 수정하면 됩니다)
# =============================================================================
#  DB    : NAOSPOC  |  19.24.0.0  |  Single Instance  |  ODA odb8
#  Schema: aosora   |  Table: TBAIIMGLOG01M
#  Dump  : /test_26aipoc/testdbdata/  (2023×3 + 2024×10)
# =============================================================================

# ---------------- Oracle 환경 ----------------
export ORACLE_SID="NAOSPOC"
export ORACLE_HOME="/u01/app/oracle/product/19.0.0.0/dbhome_1"
export PATH="$ORACLE_HOME/bin:$PATH"
export LD_LIBRARY_PATH="$ORACLE_HOME/lib:$LD_LIBRARY_PATH"

# OS 인증 (/ as sysdba) 사용 — 패스워드 파일 방식은 아래 주석 참고
DBA_CONNECT="/ as sysdba"
# 패스워드 파일 방식일 경우 아래 두 줄 활성화
# DBA_PASS="★SYS패스워드★"
# DBA_CONNECT="sys/${DBA_PASS}@${ORACLE_SID} as sysdba"

# ---------------- 대상 스키마 (aosora는 ODA 프로비저닝 시 생성됨) ----------------
TARGET_USER="AOSORA"
TARGET_PASS="★aosora패스워드★"    # ALTER USER 시 사용 (기존 패스워드 유지 가능)

# ---------------- Tablespace ----------------
TBS_DATA="IMGLOG_DATA_TBS"         # 테이블 Row 데이터
TBS_LOB="IMGLOG_LOB_TBS"          # CLOB 전용 분리 (100G+ 여유)

TBS_DATA_SIZE="50G"
TBS_LOB_SIZE="250G"               # 100G CLOB × 안전 여유

# ODA ASM Diskgroup — 실제 DG명 확인: SELECT name FROM v$asm_diskgroup;
# ODA 표준: DATA / RECO  (또는 DATAC1 / RECOC1)
ASM_DG_DATA="+DATA"               # ★ 확인 후 수정

# ---------------- 덤프 파일 경로 ----------------
DUMP_BASE="/test_26aipoc/testdbdata"

ORA_DIR_NAME="IMGLOG_DUMP_DIR"    # Oracle Directory 오브젝트명 (하나로 통합)
ORA_LOG_DIR="IMGLOG_LOG_DIR"
IMPDP_LOG_DIR="/tmp/impdp_logs"   # OS 로그 경로

# ── 2023년 덤프 (3개 / 파일명 확인됨) ────────────────────────────────────
DUMP_FILES_2023=(
  "1.TBAIIMGLOG01M_2023_01.dmp"
  "1.TBAIIMGLOG01M_2023_02.dmp"
  "1.TBAIIMGLOG01M_2023_03.dmp"
)

# ── 2024년 덤프 (10개 / _02 확인, 나머지 파일명 ls로 재확인 필요) ───────
DUMP_FILES_2024=(
  "1.TBAIIMGLOG01M_2024_01.dmp"   # ★ ls로 존재 확인
  "1.TBAIIMGLOG01M_2024_02.dmp"   # 확인됨
  "1.TBAIIMGLOG01M_2024_03.dmp"   # ★ 확인
  "1.TBAIIMGLOG01M_2024_04.dmp"   # ★ 확인
  "1.TBAIIMGLOG01M_2024_05.dmp"   # ★ 확인
  "1.TBAIIMGLOG01M_2024_06.dmp"   # ★ 확인
  "1.TBAIIMGLOG01M_2024_07.dmp"   # ★ 확인
  "1.TBAIIMGLOG01M_2024_08.dmp"   # ★ 확인
  "1.TBAIIMGLOG01M_2024_09.dmp"   # ★ 확인
  "1.TBAIIMGLOG01M_2024_10.dmp"   # ★ 확인
)

# ---------------- 임포트 대상 ----------------
SRC_TABLE="TBAIIMGLOG01M"

# 덤프 내 원본 스키마명 — expdp 생성 DB의 스키마 (aosora와 다를 수 있음)
# 확인: strings 1.TBAIIMGLOG01M_2023_01.dmp | grep -i "SCHEMA_LIST" | head -5
SRC_SCHEMA="AOSORA"               # ★ 원본 스키마명 확인 후 수정
REMAP_SCHEMA="${SRC_SCHEMA}:${TARGET_USER}"   # 같으면 impdp에서 생략 가능

# ---------------- impdp 튜닝 ----------------
# ODA odb8 = 8 OCPU → PARALLEL 4 적정 (로딩 중 서비스 영향 최소화)
PARALLEL_DEGREE=4
