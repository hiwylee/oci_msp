-- =============================================================================
--  06_verify.sql  —  임포트 결과 검증
--  실행 : sqlplus / as sysdba @06_verify.sql
-- =============================================================================
--  ★ 변수 수정: _lib/vars.sql  (TABLE_OWNER, TABLE_NAME, TBS_DATA, TBS_LOB)
-- =============================================================================

@@_lib/vars.sql

SET LINESIZE 130
SET PAGESIZE 60
SET FEEDBACK OFF
PROMPT
PROMPT ================================================================
PROMPT  STEP 6 : 임포트 결과 검증
PROMPT  대상: &&TABLE_OWNER..&&TABLE_NAME
PROMPT ================================================================

-- ── 1. 테이블 행수 확인 ──────────────────────────────────────────────────
PROMPT
PROMPT [1] &&TABLE_OWNER 스키마 테이블 행수
PROMPT ---------------------------------------------------------------
SELECT owner, table_name, num_rows, last_analyzed
FROM   dba_tables
WHERE  owner = '&&TABLE_OWNER'
ORDER  BY num_rows DESC NULLS LAST;

-- ── 2. LOB 세그먼트 크기 확인 ────────────────────────────────────────────
PROMPT
PROMPT [2] &&TABLE_NAME LOB 세그먼트 크기  (100GB 이상이어야 정상)
PROMPT ---------------------------------------------------------------
SELECT s.owner, s.segment_name, s.segment_type,
       ROUND(SUM(s.bytes)/1024/1024/1024, 2) AS size_gb
FROM   dba_segments s
WHERE  s.owner = '&&TABLE_OWNER'
  AND  s.segment_type IN ('TABLE','LOBSEGMENT','LOBINDEX')
GROUP  BY s.owner, s.segment_name, s.segment_type
ORDER  BY size_gb DESC;

-- ── 3. Tablespace 사용량 확인 ─────────────────────────────────────────────
PROMPT
PROMPT [3] &&TBS_DATA / &&TBS_LOB 사용량
PROMPT ---------------------------------------------------------------
SELECT df.tablespace_name,
       ROUND(SUM(df.bytes)/1024/1024/1024, 2)              AS total_gb,
       ROUND(SUM(df.bytes)/1024/1024/1024, 2)
         - ROUND(NVL(SUM(fs.bytes),0)/1024/1024/1024, 2)   AS used_gb,
       ROUND(NVL(SUM(fs.bytes),0)/1024/1024/1024, 2)       AS free_gb
FROM   dba_data_files df
LEFT JOIN dba_free_space fs ON df.tablespace_name = fs.tablespace_name
WHERE  df.tablespace_name IN ('&&TBS_DATA','&&TBS_LOB')
GROUP  BY df.tablespace_name;

-- ── 4. LOB 컬럼 메타데이터 확인 ──────────────────────────────────────────
PROMPT
PROMPT [4] &&TABLE_NAME LOB 컬럼 정보
PROMPT ---------------------------------------------------------------
SELECT owner, table_name, column_name, segment_name,
       tablespace_name, logging, in_row, securefile
FROM   dba_lobs
WHERE  owner = '&&TABLE_OWNER'
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
PROMPT [6] INVALID 오브젝트
PROMPT ---------------------------------------------------------------
SELECT object_type, object_name, status
FROM   dba_objects
WHERE  owner  = '&&TABLE_OWNER'
  AND  status = 'INVALID'
ORDER  BY object_type, object_name;

-- ── 7. 재컴파일 (필요시 주석 해제) ───────────────────────────────────────
PROMPT
PROMPT [7] (필요시) 비유효 오브젝트 재컴파일
PROMPT ---------------------------------------------------------------
-- EXEC UTL_RECOMP.RECOMP_SCHEMA('&&TABLE_OWNER');

PROMPT
PROMPT ================================================================
PROMPT  검증 완료.
PROMPT  - num_rows = 0 : COUNT(*) 직접 확인 또는 통계 수동 수집
PROMPT  - error_count > 0 : 로그파일(/tmp/impdp_logs/) 상세 확인
PROMPT  - LOB size_gb 작음 : CLOB 로딩 누락 가능성 재확인
PROMPT ================================================================
PROMPT
