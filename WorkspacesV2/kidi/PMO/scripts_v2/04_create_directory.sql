-- =============================================================================
--  04_create_directory.sql  —  Oracle Directory 오브젝트 등록
--  실행 : sqlplus / as sysdba @04_create_directory.sql
-- =============================================================================
--  ★ 변수 수정: _lib/vars.sql  (TABLE_OWNER, ORA_DIR, LOG_DIR)
-- =============================================================================

@@_lib/vars.sql

SET ECHO ON
PROMPT
PROMPT ================================================================
PROMPT  STEP 4 : Oracle Directory 오브젝트 생성
PROMPT  ORA_DIR=&&ORA_DIR  LOG_DIR=&&LOG_DIR
PROMPT ================================================================

PROMPT
PROMPT [사전확인] 덤프 파일 목록
PROMPT ---------------------------------------------------------------
HOST ls -lh /test_26aipoc/testdbdata/

-- ── 덤프 Directory ────────────────────────────────────────────────────────
PROMPT
PROMPT [1] 덤프 Directory: &&ORA_DIR
PROMPT ---------------------------------------------------------------
CREATE OR REPLACE DIRECTORY &&ORA_DIR
  AS '/test_26aipoc/testdbdata';

GRANT READ, WRITE ON DIRECTORY &&ORA_DIR TO &&TABLE_OWNER;

-- ── 로그 Directory ────────────────────────────────────────────────────────
PROMPT
PROMPT [2] 로그 Directory: &&LOG_DIR
PROMPT ---------------------------------------------------------------
HOST mkdir -p /tmp/impdp_logs

CREATE OR REPLACE DIRECTORY &&LOG_DIR
  AS '/tmp/impdp_logs';

GRANT READ, WRITE ON DIRECTORY &&LOG_DIR TO &&TABLE_OWNER;

-- ── 결과 확인 ────────────────────────────────────────────────────────────
PROMPT
PROMPT [확인] 등록된 Directory
PROMPT ---------------------------------------------------------------
SET ECHO OFF
SELECT directory_name, directory_path
FROM   dba_directories
WHERE  directory_name IN ('&&ORA_DIR','&&LOG_DIR')
ORDER  BY directory_name;

PROMPT
PROMPT ================================================================
PROMPT  완료. 다음: 05_run_impdp.sh
PROMPT ================================================================
PROMPT
