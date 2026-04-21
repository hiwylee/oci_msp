-- =============================================================================
--  99_rollback.sql  —  생성 오브젝트 정리 (재시작 또는 롤백 시)
--  DB   : NAOSPOC  |  실행: sqlplus / as sysdba @99_rollback.sql
-- =============================================================================
--  ⚠ 경고:
--    - aosora 계정은 ODA 프로비저닝 계정이므로 DROP하지 않음
--    - Tablespace와 Directory만 삭제 (aosora 내 TBAIIMGLOG01M 테이블 포함)
--    - 실행 전 반드시 내용을 확인하세요
-- =============================================================================

SET ECHO ON
PROMPT
PROMPT ================================================================
PROMPT  ROLLBACK : IMGLOG 관련 오브젝트 삭제
PROMPT  (aosora 계정 자체는 유지 — Tablespace/Table/Directory만 삭제)
PROMPT ================================================================

-- ── 1. TBAIIMGLOG01M 테이블 삭제 (CLOB 포함) ────────────────────────────
PROMPT
PROMPT [1] AOSORA.TBAIIMGLOG01M 테이블 삭제
PROMPT ---------------------------------------------------------------
DROP TABLE AOSORA.TBAIIMGLOG01M PURGE;

-- ── 2. Quota 제거 ─────────────────────────────────────────────────────────
PROMPT
PROMPT [2] aosora Tablespace Quota 제거
PROMPT ---------------------------------------------------------------
ALTER USER AOSORA QUOTA 0 ON IMGLOG_DATA_TBS;
ALTER USER AOSORA QUOTA 0 ON IMGLOG_LOB_TBS;

-- ── 3. Tablespace 삭제 ────────────────────────────────────────────────────
PROMPT
PROMPT [3] IMGLOG_DATA_TBS 삭제
PROMPT ---------------------------------------------------------------
DROP TABLESPACE IMGLOG_DATA_TBS
  INCLUDING CONTENTS AND DATAFILES
  CASCADE CONSTRAINTS;

PROMPT
PROMPT [4] IMGLOG_LOB_TBS 삭제
PROMPT ---------------------------------------------------------------
DROP TABLESPACE IMGLOG_LOB_TBS
  INCLUDING CONTENTS AND DATAFILES
  CASCADE CONSTRAINTS;

-- ── 4. Directory 삭제 ─────────────────────────────────────────────────────
PROMPT
PROMPT [5] Directory 오브젝트 삭제
PROMPT ---------------------------------------------------------------
DROP DIRECTORY IMGLOG_DUMP_DIR;
DROP DIRECTORY IMGLOG_LOG_DIR;

-- ── 5. impdp 권한 회수 (필요시) ──────────────────────────────────────────
PROMPT
PROMPT [6] IMP_FULL_DATABASE 권한 회수 (선택)
PROMPT ---------------------------------------------------------------
-- REVOKE IMP_FULL_DATABASE FROM AOSORA;  -- 필요시 주석 해제

-- ── 결과 확인 ─────────────────────────────────────────────────────────────
PROMPT
PROMPT [확인] 삭제 후 잔존 여부
PROMPT ---------------------------------------------------------------
SET ECHO OFF
SELECT COUNT(*) AS remaining_tbs
FROM   dba_tablespaces
WHERE  tablespace_name IN ('IMGLOG_DATA_TBS','IMGLOG_LOB_TBS');

SELECT COUNT(*) AS remaining_dirs
FROM   dba_directories
WHERE  directory_name IN ('IMGLOG_DUMP_DIR','IMGLOG_LOG_DIR');

SELECT COUNT(*) AS remaining_tables
FROM   dba_tables
WHERE  owner = 'AOSORA' AND table_name = 'TBAIIMGLOG01M';

PROMPT
PROMPT ================================================================
PROMPT  삭제 완료. 모든 항목이 0 이어야 합니다.
PROMPT  재임포트: 02_create_tablespace.sql 부터 다시 시작
PROMPT ================================================================
PROMPT
