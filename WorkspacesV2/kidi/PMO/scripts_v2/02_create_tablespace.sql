-- =============================================================================
--  02_create_tablespace.sql  —  Tablespace 생성
--  DB   : NAOSPOC  |  19.24.0.0  |  SI  |  ASM
--  실행 : sqlplus / as sysdba @02_create_tablespace.sql
-- =============================================================================
--  ★ 변수 수정: _lib/vars.sql  (TBS_DATA, TBS_LOB, ASM_DG)
-- =============================================================================

@@_lib/vars.sql

SET ECHO ON
SET TIMING ON
PROMPT
PROMPT ================================================================
PROMPT  STEP 2 : Tablespace 생성  (NAOSPOC / ASM)
PROMPT  TBS_DATA=&&TBS_DATA  TBS_LOB=&&TBS_LOB
PROMPT ================================================================

-- ── 사전 확인: ASM Diskgroup ─────────────────────────────────────────────
PROMPT
PROMPT [사전확인] ASM Diskgroup 여유 공간  (300GB 이상 권장)
PROMPT ---------------------------------------------------------------
SET ECHO OFF
SELECT name,
       ROUND(total_mb/1024,1) AS total_gb,
       ROUND(free_mb/1024,1)  AS free_gb
FROM   v$asm_diskgroup
ORDER  BY name;
SET ECHO ON

-- ── DATA Tablespace ──────────────────────────────────────────────────────
PROMPT
PROMPT [1] &&TBS_DATA 생성 (50G, autoextend)
PROMPT ---------------------------------------------------------------
CREATE TABLESPACE &&TBS_DATA
  DATAFILE '&&ASM_DG'
    SIZE 50G
    AUTOEXTEND ON NEXT 10G MAXSIZE UNLIMITED
  SEGMENT SPACE MANAGEMENT AUTO
  EXTENT MANAGEMENT LOCAL AUTOALLOCATE
  NOLOGGING;

-- ── LOB Tablespace ────────────────────────────────────────────────────────
PROMPT
PROMPT [2] &&TBS_LOB 생성 (250G, autoextend)
PROMPT ---------------------------------------------------------------
CREATE TABLESPACE &&TBS_LOB
  DATAFILE '&&ASM_DG'
    SIZE 250G
    AUTOEXTEND ON NEXT 20G MAXSIZE UNLIMITED
  SEGMENT SPACE MANAGEMENT AUTO
  EXTENT MANAGEMENT LOCAL AUTOALLOCATE
  NOLOGGING;

-- ── 결과 확인 ────────────────────────────────────────────────────────────
PROMPT
PROMPT [확인] 생성된 Tablespace
PROMPT ---------------------------------------------------------------
SET ECHO OFF
SELECT df.tablespace_name, t.status, t.logging,
       ROUND(SUM(df.bytes)/1024/1024/1024, 1) AS alloc_gb
FROM   dba_data_files df
JOIN   dba_tablespaces t ON df.tablespace_name = t.tablespace_name
WHERE  df.tablespace_name IN ('&&TBS_DATA','&&TBS_LOB')
GROUP  BY df.tablespace_name, t.status, t.logging;

PROMPT
PROMPT ================================================================
PROMPT  완료. 다음: 03_create_user.sql
PROMPT ================================================================
PROMPT
