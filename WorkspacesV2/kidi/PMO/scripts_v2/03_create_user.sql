-- =============================================================================
--  03_create_user.sql  —  사용자 설정 + 권한 부여
--  DB   : NAOSPOC  |  aosora 는 ODA 프로비저닝 시 이미 생성됨
--  실행 : sqlplus / as sysdba @03_create_user.sql
-- =============================================================================
--  ★ 변수 수정: _lib/vars.sql  (TABLE_OWNER, TBS_DATA, TBS_LOB)
-- =============================================================================

@@_lib/vars.sql

SET ECHO ON
PROMPT
PROMPT ================================================================
PROMPT  STEP 3 : &&TABLE_OWNER 사용자 Tablespace 설정 + 임포트 권한
PROMPT ================================================================

-- ── 기존 상태 확인 ───────────────────────────────────────────────────────
PROMPT
PROMPT [사전확인] &&TABLE_OWNER 계정 상태
PROMPT ---------------------------------------------------------------
SET ECHO OFF
SELECT username, account_status, default_tablespace, temporary_tablespace, created
FROM   dba_users
WHERE  username = '&&TABLE_OWNER';
SET ECHO ON

-- ── Default Tablespace + Quota ────────────────────────────────────────────
PROMPT
PROMPT [1] &&TABLE_OWNER Default Tablespace → &&TBS_DATA
PROMPT ---------------------------------------------------------------
ALTER USER &&TABLE_OWNER
  DEFAULT TABLESPACE &&TBS_DATA
  TEMPORARY TABLESPACE TEMP;

PROMPT
PROMPT [2] Quota 부여
PROMPT ---------------------------------------------------------------
ALTER USER &&TABLE_OWNER QUOTA UNLIMITED ON &&TBS_DATA;
ALTER USER &&TABLE_OWNER QUOTA UNLIMITED ON &&TBS_LOB;

-- ── impdp 권한 ───────────────────────────────────────────────────────────
PROMPT
PROMPT [3] IMP_FULL_DATABASE 권한 부여
PROMPT ---------------------------------------------------------------
GRANT IMP_FULL_DATABASE TO &&TABLE_OWNER;

-- ── 결과 확인 ────────────────────────────────────────────────────────────
PROMPT
PROMPT [확인] &&TABLE_OWNER 설정 결과
PROMPT ---------------------------------------------------------------
SET ECHO OFF
SELECT username, account_status, default_tablespace
FROM   dba_users WHERE username = '&&TABLE_OWNER';

SELECT privilege FROM dba_sys_privs WHERE grantee = '&&TABLE_OWNER' ORDER BY 1;

SELECT tablespace_name,
       DECODE(max_bytes,-1,'UNLIMITED', TO_CHAR(ROUND(max_bytes/1024/1024/1024,1))||'GB') quota
FROM   dba_ts_quotas WHERE username = '&&TABLE_OWNER';

PROMPT
PROMPT ================================================================
PROMPT  완료. 다음: 04_create_directory.sql
PROMPT ================================================================
PROMPT
