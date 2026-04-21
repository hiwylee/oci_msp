-- =============================================================================
--  03_create_user.sql  —  aosora 사용자 설정 + 권한 부여
--  DB   : NAOSPOC  |  aosora 는 ODA 프로비저닝 시 이미 생성됨
--  실행 : sqlplus / as sysdba @03_create_user.sql
-- =============================================================================
--  ※ CREATE USER 대신 ALTER USER + QUOTA 부여 방식 사용
--     (이미 존재하는 경우 CREATE 시 ORA-01920 발생 방지)
-- =============================================================================

SET ECHO ON
PROMPT
PROMPT ================================================================
PROMPT  STEP 3 : aosora 사용자 Tablespace 설정 + 임포트 권한
PROMPT ================================================================

-- ── aosora 기존 상태 확인 ────────────────────────────────────────────────
PROMPT
PROMPT [사전확인] aosora 계정 상태
PROMPT ---------------------------------------------------------------
SET ECHO OFF
SELECT username, account_status, default_tablespace, temporary_tablespace, created
FROM   dba_users
WHERE  username = 'AOSORA';
SET ECHO ON

-- ── Default Tablespace 변경 + CLOB용 Quota ───────────────────────────────
PROMPT
PROMPT [1] aosora Default Tablespace → IMGLOG_DATA_TBS
PROMPT ---------------------------------------------------------------
ALTER USER AOSORA
  DEFAULT TABLESPACE IMGLOG_DATA_TBS
  TEMPORARY TABLESPACE TEMP;

PROMPT
PROMPT [2] Quota 부여 (DATA + LOB)
PROMPT ---------------------------------------------------------------
ALTER USER AOSORA QUOTA UNLIMITED ON IMGLOG_DATA_TBS;
ALTER USER AOSORA QUOTA UNLIMITED ON IMGLOG_LOB_TBS;

-- ── impdp 실행 권한 ──────────────────────────────────────────────────────
PROMPT
PROMPT [3] impdp 권한 부여
PROMPT ---------------------------------------------------------------
GRANT IMP_FULL_DATABASE TO AOSORA;

-- ── 결과 확인 ────────────────────────────────────────────────────────────
PROMPT
PROMPT [확인] aosora 권한 목록
PROMPT ---------------------------------------------------------------
SET ECHO OFF
SELECT username, account_status, default_tablespace
FROM   dba_users WHERE username = 'AOSORA';

SELECT privilege FROM dba_sys_privs WHERE grantee = 'AOSORA' ORDER BY 1;

SELECT tablespace_name, max_bytes
FROM   dba_ts_quotas WHERE username = 'AOSORA';

PROMPT
PROMPT ================================================================
PROMPT  완료. 다음: 04_create_directory.sql
PROMPT ================================================================
PROMPT
