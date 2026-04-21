-- =============================================================================
--  04_create_directory.sql  —  Oracle Directory 오브젝트 등록
--  DB   : NAOSPOC  |  Table: TBAIIMGLOG01M
--  실행 : sqlplus / as sysdba @04_create_directory.sql
-- =============================================================================
--  ★ 전제: OS에 덤프 경로와 로그 경로가 존재해야 함
--     확인: ! ls /test_26aipoc/testdbdata/
--           ! mkdir -p /tmp/impdp_logs
-- =============================================================================

SET ECHO ON
PROMPT
PROMPT ================================================================
PROMPT  STEP 4 : Oracle Directory 오브젝트 생성
PROMPT ================================================================

-- ── OS 경로 / 파일 목록 확인 ─────────────────────────────────────────────
PROMPT
PROMPT [사전확인] 덤프 파일 목록  (2023×3 + 2024×10 = 13개 확인)
PROMPT ---------------------------------------------------------------
HOST ls -lh /test_26aipoc/testdbdata/

-- ── 덤프 디렉토리 (2023 / 2024 같은 경로 → 하나로 통합) ──────────────────
PROMPT
PROMPT [1] 덤프 Directory 등록: IMGLOG_DUMP_DIR
PROMPT ---------------------------------------------------------------
CREATE OR REPLACE DIRECTORY IMGLOG_DUMP_DIR
  AS '/test_26aipoc/testdbdata';

GRANT READ, WRITE ON DIRECTORY IMGLOG_DUMP_DIR TO AOSORA;

-- ── impdp 로그 디렉토리 ───────────────────────────────────────────────────
PROMPT
PROMPT [2] 로그 Directory 등록: IMGLOG_LOG_DIR
PROMPT ---------------------------------------------------------------
HOST mkdir -p /tmp/impdp_logs

CREATE OR REPLACE DIRECTORY IMGLOG_LOG_DIR
  AS '/tmp/impdp_logs';

GRANT READ, WRITE ON DIRECTORY IMGLOG_LOG_DIR TO AOSORA;

-- ── 등록 결과 확인 ───────────────────────────────────────────────────────
PROMPT
PROMPT [확인] 등록된 Directory 목록
PROMPT ---------------------------------------------------------------
SET ECHO OFF
SELECT directory_name, directory_path
FROM   dba_directories
WHERE  directory_name IN ('IMGLOG_DUMP_DIR','IMGLOG_LOG_DIR')
ORDER  BY directory_name;

PROMPT
PROMPT ================================================================
PROMPT  완료. 다음: 05_run_impdp.sh
PROMPT ================================================================
PROMPT
