-- =============================================================================
--  01_precheck.sql  —  사전 환경 점검
--  실행: sqlplus / as sysdba @01_precheck.sql
-- =============================================================================
--  ★ 변수 수정: _lib/vars.sql  (TABLE_OWNER, TBS_DATA, TBS_LOB)
-- =============================================================================

@@_lib/vars.sql

SET LINESIZE 120
SET PAGESIZE 50
SET FEEDBACK OFF
PROMPT
PROMPT ================================================================
PROMPT  STEP 1 : 사전 환경 점검  (&&TABLE_OWNER / &&TABLE_NAME)
PROMPT ================================================================

-- ── 1. Force Logging 확인 (NOLOGGING 효과 여부) ──────────────────────────
PROMPT
PROMPT [1] Force Logging 상태  (YES면 NOLOGGING 무효 → ADG 주의)
PROMPT ---------------------------------------------------------------
SELECT name, force_logging, log_mode FROM v$database;

-- ── 2. Undo Tablespace 여유 공간 ─────────────────────────────────────────
PROMPT
PROMPT [2] Undo Tablespace 가용 공간
PROMPT ---------------------------------------------------------------
SELECT tablespace_name,
       ROUND(SUM(bytes)/1024/1024/1024, 2) AS free_gb
FROM   dba_free_space
WHERE  tablespace_name LIKE 'UNDO%'
GROUP  BY tablespace_name;

-- ── 3. Undo 보존 설정 ────────────────────────────────────────────────────
PROMPT
PROMPT [3] Undo Retention 설정 (초)
PROMPT ---------------------------------------------------------------
SELECT name, value FROM v$parameter WHERE name IN ('undo_retention','undo_tablespace');

-- ── 4. TEMP Tablespace 여유 ──────────────────────────────────────────────
PROMPT
PROMPT [4] TEMP Tablespace 여유 공간
PROMPT ---------------------------------------------------------------
SELECT tablespace_name,
       ROUND(SUM(bytes_free)/1024/1024/1024, 2) AS free_gb
FROM   v$temp_space_header
GROUP  BY tablespace_name;

-- ── 5. ASM Diskgroup 여유 공간 ───────────────────────────────────────────
PROMPT
PROMPT [5] ASM Diskgroup 여유 공간  (LOB TBS 200GB 이상 필요)
PROMPT ---------------------------------------------------------------
SELECT group_number, name,
       ROUND(total_mb/1024, 1) AS total_gb,
       ROUND(free_mb/1024, 1)  AS free_gb,
       ROUND(free_mb/total_mb*100, 1) AS free_pct
FROM   v$asm_diskgroup
ORDER  BY name;

-- ── 6. Archive Log 공간 ──────────────────────────────────────────────────
PROMPT
PROMPT [6] Archive Log 목적지 여유  (로딩 중 급증 가능)
PROMPT ---------------------------------------------------------------
SELECT dest_name, status, target, archiver,
       ROUND(space_limit/1024/1024/1024, 1) AS limit_gb,
       ROUND(space_used/1024/1024/1024, 1)  AS used_gb
FROM   v$archive_dest
WHERE  status = 'VALID' AND target = 'PRIMARY';

-- ── 7. PGA / SGA 설정 ────────────────────────────────────────────────────
PROMPT
PROMPT [7] PGA / SGA 설정  (impdp 병렬 시 PGA 소비 증가)
PROMPT ---------------------------------------------------------------
SELECT name, ROUND(value/1024/1024/1024, 2) AS gb
FROM   v$parameter
WHERE  name IN ('pga_aggregate_target','sga_target','sga_max_size')
ORDER  BY name;

-- ── 8. 현재 활성 세션 / 부하 확인 ────────────────────────────────────────
PROMPT
PROMPT [8] 현재 활성 세션 수  (impdp 전 부하 확인)
PROMPT ---------------------------------------------------------------
SELECT status, COUNT(*) AS cnt
FROM   v$session
WHERE  type = 'USER'
GROUP  BY status;

-- ── 9. 기존 동명 Tablespace / User 존재 확인 ────────────────────────────
PROMPT
PROMPT [9] 기존 Tablespace 목록  (중복 생성 방지)
PROMPT ---------------------------------------------------------------
SELECT tablespace_name, status,
       ROUND(SUM(bytes)/1024/1024/1024, 2) AS size_gb
FROM   dba_data_files
WHERE  tablespace_name IN ('&&TBS_DATA','&&TBS_LOB')
GROUP  BY tablespace_name, status;

PROMPT
PROMPT [10] 기존 사용자 확인
PROMPT ---------------------------------------------------------------
SELECT username, account_status, created
FROM   dba_users
WHERE  username = '&&TABLE_OWNER';

PROMPT
PROMPT ================================================================
PROMPT  점검 완료. 위 결과를 확인 후 다음 단계로 진행하세요.
PROMPT  ASM free < 250GB 또는 Undo free < 20GB 이면 DBA와 협의 필요.
PROMPT ================================================================
PROMPT
