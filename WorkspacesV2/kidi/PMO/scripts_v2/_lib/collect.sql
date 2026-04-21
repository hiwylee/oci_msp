-- =============================================================================
--  _lib/collect.sql  —  데이터·블록 상태 수집 (baseline / 비교 공통 사용)
--  실행: sqlplus / as sysdba @_lib/collect.sql (05_run_impdp.sh에서 호출)
--  출력: 고정 포맷 KEY=VALUE  →  diff로 비교 가능
-- =============================================================================
--  대상: AOSORA.TBAIIMGLOG01M  /  DB: NAOSPOC
-- =============================================================================

SET ECHO OFF
SET FEEDBACK OFF
SET HEADING OFF
SET PAGESIZE 0
SET LINESIZE 200
SET TRIMSPOOL ON
SET VERIFY OFF

-- 출력 파일은 호출 스크립트에서 SPOOL 설정
-- 구분자: [SECTION] KEY=VALUE 형식으로 grep/diff 용이

PROMPT ============================================================
PROMPT  수집 시각
PROMPT ============================================================
SELECT '[META] collected_at=' || TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') FROM DUAL;
SELECT '[META] db_name='      || name         FROM v$database;
SELECT '[META] db_version='   || version      FROM v$instance;
SELECT '[META] open_mode='    || open_mode    FROM v$database;

PROMPT
PROMPT ============================================================
PROMPT  1. 행수 / NULL LOB 확인
PROMPT ============================================================
-- COUNT(*): 가장 중요한 기준값
SELECT '[ROW] total_count=' || COUNT(*) FROM AOSORA.TBAIIMGLOG01M;

-- LOB 컬럼명은 dba_lobs에서 동적으로 조회 후 아래 SQL에 반영
-- ★ 실제 LOB 컬럼명을 확인하여 col_name 부분을 수정하세요
--    SELECT column_name FROM dba_lobs WHERE owner='AOSORA' AND table_name='TBAIIMGLOG01M';
-- 예시 (컬럼명이 확인되면 주석 해제):
-- SELECT '[ROW] null_lob_count=' || COUNT(*)
-- FROM   AOSORA.TBAIIMGLOG01M
-- WHERE  ★LOB_COLUMN★ IS NULL;

-- SELECT '[ROW] lob_len_sum='    || SUM(DBMS_LOB.GETLENGTH(★LOB_COLUMN★))
-- FROM   AOSORA.TBAIIMGLOG01M;

-- SELECT '[ROW] lob_len_avg='    || ROUND(AVG(DBMS_LOB.GETLENGTH(★LOB_COLUMN★)),0)
-- FROM   AOSORA.TBAIIMGLOG01M;

PROMPT
PROMPT ============================================================
PROMPT  2. 세그먼트 크기 (메타데이터 기반 — 즉시 조회)
PROMPT ============================================================
SELECT '[SEG] ' || segment_type || '_' || segment_name || '='
       || ROUND(SUM(bytes)/1024/1024/1024, 4) || 'GB'
FROM   dba_segments
WHERE  owner = 'AOSORA'
  AND  segment_name LIKE '%TBAIIMGLOG01M%'
GROUP  BY segment_type, segment_name
ORDER  BY segment_type, segment_name;

SELECT '[SEG] total_all_segments_gb='
       || ROUND(SUM(bytes)/1024/1024/1024, 4)
FROM   dba_segments
WHERE  owner = 'AOSORA';

PROMPT
PROMPT ============================================================
PROMPT  3. dba_tables 통계 (마지막 analyze 기준)
PROMPT ============================================================
SELECT '[STAT] num_rows='     || NVL(TO_CHAR(num_rows),'NULL')
FROM   dba_tables
WHERE  owner='AOSORA' AND table_name='TBAIIMGLOG01M';

SELECT '[STAT] blocks='       || NVL(TO_CHAR(blocks),'NULL')
FROM   dba_tables
WHERE  owner='AOSORA' AND table_name='TBAIIMGLOG01M';

SELECT '[STAT] avg_row_len='  || NVL(TO_CHAR(avg_row_len),'NULL')
FROM   dba_tables
WHERE  owner='AOSORA' AND table_name='TBAIIMGLOG01M';

SELECT '[STAT] last_analyzed=' || NVL(TO_CHAR(last_analyzed,'YYYY-MM-DD HH24:MI:SS'),'NULL')
FROM   dba_tables
WHERE  owner='AOSORA' AND table_name='TBAIIMGLOG01M';

PROMPT
PROMPT ============================================================
PROMPT  4. LOB 메타데이터
PROMPT ============================================================
SELECT '[LOB] column=' || column_name
       || ' tbs=' || tablespace_name
       || ' securefile=' || securefile
       || ' logging=' || logging
       || ' in_row=' || in_row
FROM   dba_lobs
WHERE  owner='AOSORA' AND table_name='TBAIIMGLOG01M'
ORDER  BY column_name;

PROMPT
PROMPT ============================================================
PROMPT  5. 인덱스 상태
PROMPT ============================================================
SELECT '[IDX] ' || index_name || '=' || status
       || ' type=' || index_type
       || ' blevel=' || NVL(TO_CHAR(blevel),'NULL')
FROM   dba_indexes
WHERE  table_owner='AOSORA' AND table_name='TBAIIMGLOG01M'
ORDER  BY index_name;

PROMPT
PROMPT ============================================================
PROMPT  6. 블록 손상 현황 (RMAN VALIDATE 후 갱신됨)
PROMPT ============================================================
SELECT '[BLOCK] corruption_count=' || COUNT(*)
FROM   v$database_block_corruption;

SELECT '[BLOCK] ' || file#         || '_'
       || block#      || '_'
       || blocks      || '_'
       || corruption_type
FROM   v$database_block_corruption
ORDER  BY file#, block#;

PROMPT
PROMPT ============================================================
PROMPT  7. 데이터 행 지문 (ORA_HASH 기반 — 상위 100만 행 샘플)
PROMPT     ★ 전체 행 수가 적으면 WHERE 조건 제거 권장
PROMPT ============================================================
-- 비LOB 컬럼들의 ORA_HASH 합계로 데이터 변조 여부 빠른 확인
-- ★ PRIMARY KEY 컬럼이 확인되면 해당 컬럼으로 교체 권장
SELECT '[HASH] rowid_ora_hash_sum=' ||
       SUM(ORA_HASH(ROWIDTOCHAR(ROWID)))
FROM   AOSORA.TBAIIMGLOG01M
WHERE  ROWNUM <= 1000000;

SELECT '[HASH] sample_row_count=' || COUNT(*)
FROM   AOSORA.TBAIIMGLOG01M
WHERE  ROWNUM <= 1000000;

PROMPT
PROMPT ============================================================
PROMPT  수집 완료
PROMPT ============================================================
