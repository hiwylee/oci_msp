-- =============================================================================
--  _lib/vars.sql  —  SQL*Plus 공통 변수 정의
--  ★ 여기만 수정하면 모든 SQL 스크립트에 자동 반영됩니다
--  각 SQL 파일 상단에서  @@_lib/vars.sql  (루트 기준) 또는
--                        @@vars.sql       (_lib/ 내부 기준) 으로 호출
-- =============================================================================

-- 스키마 / 테이블
DEFINE TABLE_OWNER = 'AOSORA'
DEFINE TABLE_NAME  = 'TBAIIMGLOG01M'

-- Tablespace
DEFINE TBS_DATA    = 'IMGLOG_DATA_TBS'
DEFINE TBS_LOB     = 'IMGLOG_LOB_TBS'

-- Oracle Directory 오브젝트명
DEFINE ORA_DIR     = 'IMGLOG_DUMP_DIR'
DEFINE LOG_DIR     = 'IMGLOG_LOG_DIR'

-- ASM Diskgroup (★ 실제 DG명으로 수정)
DEFINE ASM_DG      = '+DATA'

PROMPT [vars] TABLE_OWNER=&&TABLE_OWNER  TABLE_NAME=&&TABLE_NAME
PROMPT [vars] TBS_DATA=&&TBS_DATA  TBS_LOB=&&TBS_LOB
