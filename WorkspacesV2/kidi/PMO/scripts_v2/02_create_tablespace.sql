-- =============================================================================
--  02_create_tablespace.sql  —  Tablespace 생성
--  DB   : NAOSPOC  |  19.24.0.0  |  SI  |  ASM
--  실행 : sqlplus / as sysdba @02_create_tablespace.sql
-- =============================================================================
--  ★ 사전확인: ASM Diskgroup명
--     SELECT name, state, total_mb, free_mb FROM v$asm_diskgroup;
--  ODA 표준 DG: DATA / RECO  (또는 DATAC1 / RECOC1)
-- =============================================================================

SET ECHO ON
SET TIMING ON
PROMPT
PROMPT ================================================================
PROMPT  STEP 2 : Tablespace 생성  (NAOSPOC / ASM)
PROMPT ================================================================

-- ── 사전 확인: ASM Diskgroup ─────────────────────────────────────────────
PROMPT
PROMPT [사전확인] ASM Diskgroup 여유 공간  (DATA 250GB 이상 권장)
PROMPT ---------------------------------------------------------------
SET ECHO OFF
SELECT name,
       ROUND(total_mb/1024,1) AS total_gb,
       ROUND(free_mb/1024,1)  AS free_gb
FROM   v$asm_diskgroup
ORDER  BY name;
SET ECHO ON

-- ── DATA Tablespace (Row 데이터용) ───────────────────────────────────────
PROMPT
PROMPT [1] IMGLOG_DATA_TBS 생성 (50G, autoextend)
PROMPT ---------------------------------------------------------------
CREATE TABLESPACE IMGLOG_DATA_TBS
  DATAFILE '+DATA'                        -- ★ DG명 다르면 여기 수정
    SIZE 50G
    AUTOEXTEND ON NEXT 10G MAXSIZE UNLIMITED
  SEGMENT SPACE MANAGEMENT AUTO
  EXTENT MANAGEMENT LOCAL AUTOALLOCATE
  NOLOGGING;

-- ── LOB Tablespace (CLOB 100G+ 전용) ─────────────────────────────────────
PROMPT
PROMPT [2] IMGLOG_LOB_TBS 생성 (250G, autoextend)  — CLOB 100GB 이상 여유
PROMPT ---------------------------------------------------------------
CREATE TABLESPACE IMGLOG_LOB_TBS
  DATAFILE '+DATA'                        -- ★ DG명 다르면 여기 수정
    SIZE 250G
    AUTOEXTEND ON NEXT 20G MAXSIZE UNLIMITED
  SEGMENT SPACE MANAGEMENT AUTO
  EXTENT MANAGEMENT LOCAL AUTOALLOCATE
  NOLOGGING;

-- ── 생성 결과 확인 ──────────────────────────────────────────────────────
PROMPT
PROMPT [확인] 생성된 Tablespace
PROMPT ---------------------------------------------------------------
SET ECHO OFF
SELECT df.tablespace_name, t.status, t.logging,
       ROUND(SUM(df.bytes)/1024/1024/1024, 1) AS alloc_gb
FROM   dba_data_files df
JOIN   dba_tablespaces t ON df.tablespace_name = t.tablespace_name
WHERE  df.tablespace_name IN ('IMGLOG_DATA_TBS','IMGLOG_LOB_TBS')
GROUP  BY df.tablespace_name, t.status, t.logging;

PROMPT
PROMPT ================================================================
PROMPT  완료. 다음: 03_create_user.sql
PROMPT ================================================================
PROMPT
