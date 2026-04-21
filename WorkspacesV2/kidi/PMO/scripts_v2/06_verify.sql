-- =============================================================================
--  06_verify.sql  —  임포트 결과 검증
--  실행: sqlplus / as sysdba @06_verify.sql
-- =============================================================================

SET LINESIZE 130
SET PAGESIZE 60
SET FEEDBACK OFF
PROMPT
PROMPT ================================================================
PROMPT  STEP 6 : 임포트 결과 검증
PROMPT ================================================================

-- ── 1. 테이블 행수 확인 ──────────────────────────────────────────────────
PROMPT
PROMPT [1] AOSORA 스키마 테이블 행수 (CLOB 테이블 포함)
PROMPT ---------------------------------------------------------------
SELECT owner, table_name, num_rows, last_analyzed
FROM   dba_tables
WHERE  owner = 'AOSORA'
ORDER  BY num_rows DESC NULLS LAST;

-- ── 2. LOB 세그먼트 크기 확인 ────────────────────────────────────────────
PROMPT
PROMPT [2] LOB 세그먼트 크기  (TBAIIMGLOG01M / 100GB 이상이어야 정상)
PROMPT ---------------------------------------------------------------
SELECT s.owner, s.segment_name, s.segment_type,
       ROUND(SUM(s.bytes)/1024/1024/1024, 2) AS size_gb
FROM   dba_segments s
WHERE  s.owner = 'AOSORA'
  AND  s.segment_type IN ('TABLE','LOBSEGMENT','LOBINDEX')
GROUP  BY s.owner, s.segment_name, s.segment_type
ORDER  BY size_gb DESC;

-- ── 3. Tablespace 사용량 확인 ─────────────────────────────────────────────
PROMPT
PROMPT [3] IMGLOG Tablespace 사용량
PROMPT ---------------------------------------------------------------
SELECT df.tablespace_name,
       ROUND(SUM(df.bytes)/1024/1024/1024, 2)              AS total_gb,
       ROUND(SUM(df.bytes)/1024/1024/1024, 2)
         - ROUND(NVL(SUM(fs.bytes),0)/1024/1024/1024, 2)   AS used_gb,
       ROUND(NVL(SUM(fs.bytes),0)/1024/1024/1024, 2)       AS free_gb
FROM   dba_data_files df
LEFT JOIN dba_free_space fs ON df.tablespace_name = fs.tablespace_name
WHERE  df.tablespace_name IN ('IMGLOG_DATA_TBS','IMGLOG_LOB_TBS')
GROUP  BY df.tablespace_name;

-- ── 4. LOB 컬럼 메타데이터 확인 ──────────────────────────────────────────
PROMPT
PROMPT [4] TBAIIMGLOG01M LOB 컬럼 정보
PROMPT ---------------------------------------------------------------
SELECT owner, table_name, column_name, segment_name,
       tablespace_name, logging, in_row, securefile
FROM   dba_lobs
WHERE  owner = 'AOSORA'
ORDER  BY table_name, column_name;

-- ── 5. impdp 오류 확인 ───────────────────────────────────────────────────
PROMPT
PROMPT [5] 임포트 작업 이력 (ORA- 오류 여부)
PROMPT ---------------------------------------------------------------
SELECT job_name, operation, job_mode, state,
       TO_CHAR(start_time,'YYYY-MM-DD HH24:MI:SS') AS started,
       TO_CHAR(end_time,  'YYYY-MM-DD HH24:MI:SS') AS ended,
       error_count
FROM   dba_datapump_jobs
WHERE  operation = 'IMPORT'
ORDER  BY start_time DESC
FETCH FIRST 10 ROWS ONLY;

-- ── 6. 비유효 오브젝트 확인 ──────────────────────────────────────────────
PROMPT
PROMPT [6] INVALID 오브젝트 (있으면 recompile 필요)
PROMPT ---------------------------------------------------------------
SELECT object_type, object_name, status
FROM   dba_objects
WHERE  owner  = 'AOSORA'
  AND  status = 'INVALID'
ORDER  BY object_type, object_name;

-- ── 7. INVALID가 있으면 recompile ─────────────────────────────────────────
PROMPT
PROMPT [7] (필요시) 비유효 오브젝트 일괄 재컴파일
PROMPT ---------------------------------------------------------------
-- EXEC UTL_RECOMP.RECOMP_SCHEMA('AOSORA');   -- 주석 해제 후 실행

PROMPT
PROMPT ================================================================
PROMPT  검증 완료.
PROMPT  - num_rows 가 0 이면: GATHER_SCHEMA_STATS 재실행 또는 COUNT(*) 직접 확인
PROMPT  - error_count > 0   : 로그파일(/tmp/impdp_logs/) 상세 확인
PROMPT  - LOB size_gb 작으면: CLOB 데이터 로딩 누락 가능성 → 재확인
PROMPT ================================================================
PROMPT
