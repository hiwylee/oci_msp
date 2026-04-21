-- =============================================================================
--  99_rollback.sql  —  생성 오브젝트 정리
--  실행 : sqlplus / as sysdba @99_rollback.sql
-- =============================================================================
--  ★ 변수 수정: _lib/vars.sql  (TABLE_OWNER, TABLE_NAME, TBS_DATA, TBS_LOB)
--  ⚠ aosora 계정 자체는 ODA 프로비저닝 계정이므로 DROP하지 않음
-- =============================================================================

@@_lib/vars.sql

SET ECHO ON
PROMPT
PROMPT ================================================================
PROMPT  ROLLBACK : &&TABLE_OWNER..&&TABLE_NAME 및 관련 오브젝트 삭제
PROMPT  (계정 자체는 유지 — 테이블/Tablespace/Directory만 삭제)
PROMPT ================================================================

-- ── 1. 테이블 삭제 ───────────────────────────────────────────────────────
PROMPT
PROMPT [1] &&TABLE_OWNER..&&TABLE_NAME 삭제 (CLOB 포함)
PROMPT ---------------------------------------------------------------
DROP TABLE &&TABLE_OWNER..&&TABLE_NAME PURGE;

-- ── 2. Quota 제거 ─────────────────────────────────────────────────────────
PROMPT
PROMPT [2] &&TABLE_OWNER Quota 제거
PROMPT ---------------------------------------------------------------
ALTER USER &&TABLE_OWNER QUOTA 0 ON &&TBS_DATA;
ALTER USER &&TABLE_OWNER QUOTA 0 ON &&TBS_LOB;

-- ── 3. Tablespace 삭제 ────────────────────────────────────────────────────
PROMPT
PROMPT [3] &&TBS_DATA 삭제
PROMPT ---------------------------------------------------------------
DROP TABLESPACE &&TBS_DATA
  INCLUDING CONTENTS AND DATAFILES
  CASCADE CONSTRAINTS;

PROMPT
PROMPT [4] &&TBS_LOB 삭제
PROMPT ---------------------------------------------------------------
DROP TABLESPACE &&TBS_LOB
  INCLUDING CONTENTS AND DATAFILES
  CASCADE CONSTRAINTS;

-- ── 4. Directory 삭제 ─────────────────────────────────────────────────────
PROMPT
PROMPT [5] Directory 삭제
PROMPT ---------------------------------------------------------------
DROP DIRECTORY &&ORA_DIR;
DROP DIRECTORY &&LOG_DIR;

-- ── 5. impdp 권한 회수 (선택) ─────────────────────────────────────────────
-- REVOKE IMP_FULL_DATABASE FROM &&TABLE_OWNER;

-- ── 결과 확인 ────────────────────────────────────────────────────────────
PROMPT
PROMPT [확인] 삭제 후 잔존 여부  (모두 0 이어야 정상)
PROMPT ---------------------------------------------------------------
SET ECHO OFF
SELECT COUNT(*) AS remaining_tbs
FROM   dba_tablespaces
WHERE  tablespace_name IN ('&&TBS_DATA','&&TBS_LOB');

SELECT COUNT(*) AS remaining_dirs
FROM   dba_directories
WHERE  directory_name IN ('&&ORA_DIR','&&LOG_DIR');

SELECT COUNT(*) AS remaining_tables
FROM   dba_tables
WHERE  owner = '&&TABLE_OWNER' AND table_name = '&&TABLE_NAME';

PROMPT
PROMPT ================================================================
PROMPT  완료. 재임포트: 02_create_tablespace.sql 부터 재시작
PROMPT ================================================================
PROMPT
