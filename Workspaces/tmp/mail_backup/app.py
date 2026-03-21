import streamlit as st
import os
import glob
import email
from email import policy
from email.parser import BytesParser
import pandas as pd
from datetime import datetime
# BeautifulSoup은 텍스트 미리보기 추출용으로 사용 (선택 사항)
try:
    from bs4 import BeautifulSoup
except ImportError:
    BeautifulSoup = None

# --- 페이지 설정 ---
st.set_page_config(layout="wide", page_title="EML Viewer Pro", page_icon="📧")

# --- 스타일 커스터마이징 (Outlook 느낌) ---
st.markdown("""
<style>
    /* 전체 폰트 크기 조절 */
    html, body, [class*="css"] {
        font-family: 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
    }
    .stDataFrameFix {
        font-size: 0.95em;
    }
    /* 선택된 행 강조 스타일 - Streamlit 버전에 따라 다를 수 있음 */
    [data-testid="stDataFrame"] div[role="rowgroup"] div[role="row"][aria-selected="true"] {
        background-color: #cce8ff !important;
        color: black !important;
        font-weight: 500;
    }
    /* 이메일 헤더 영역 스타일 */
    .email-header-container {
        padding: 20px;
        background-color: #ffffff;
        border-bottom: 1px solid #e0e0e0;
        margin-bottom: 20px;
    }
    .email-subject {
        margin-top: 0;
        margin-bottom: 15px;
        font-size: 1.4em;
        color: #201f1e;
    }
    .header-info {
        margin-bottom: 5px;
        color: #605e5c;
        font-size: 0.9em;
    }
    .header-label {
        font-weight: 600;
        color: #201f1e;
        margin-right: 5px;
    }
    /* 본문 컨테이너 */
    .email-body-container {
        padding: 25px;
        background-color: white;
        height: calc(100vh - 250px); /* 헤더 높이 제외한 나머지 */
        overflow-y: auto;
        border-radius: 8px;
        box-shadow: 0 1px 3px rgba(0,0,0,0.12), 0 1px 2px rgba(0,0,0,0.24);
    }
</style>
""", unsafe_allow_html=True)


# --- 헬퍼 함수: EML 파일 파싱 ---
def parse_eml(file_path):
    try:
        with open(file_path, 'rb') as f:
            # 최신 이메일 정책을 사용하여 파싱 (자동 디코딩 등 처리)
            msg = BytesParser(policy=policy.default).parse(f)

        # 기본 헤더 정보 추출 (없을 경우 기본값)
        subject = msg.get('subject', '(제목 없음)')
        from_ = msg.get('from', '(알 수 없음)')
        to_ = msg.get('to', '(알 수 없음)')
        date_str = msg.get('date', '')
        
        # 날짜 포맷팅 및 정렬용 객체 생성
        formatted_date = date_str
        dt_object = datetime.min
        try:
            if date_str:
                dt_object = email.utils.parsedate_to_datetime(date_str)
                # 보기 좋은 형식으로 변환 (예: 2023-10-27 14:30)
                formatted_date = dt_object.strftime("%Y-%m-%d %H:%M")
        except Exception:
            pass # 날짜 파싱 실패 시 원본 문자열 사용 및 정렬은 최하위로

        body_content = ""
        body_type = "text/plain"

        # 본문 추출 로직 (HTML 우선, 없으면 텍스트)
        if msg.is_multipart():
            # 가장 적절한 부분을 찾습니다. preferencelist 순서대로 찾음.
            html_part = msg.get_body(preferencelist=('html',))
            text_part = msg.get_body(preferencelist=('plain',))

            if html_part:
                body_content = html_part.get_content()
                body_type = "text/html"
            elif text_part:
                body_content = text_part.get_content()
                body_type = "text/plain"
            else:
                # Fallback: get_body가 실패할 경우 수동으로 순회
                for part in msg.walk():
                    ctype = part.get_content_type()
                    cdispo = str(part.get('Content-Disposition'))

                    # 첨부파일은 건너뜀
                    if 'attachment' in cdispo:
                        continue
                    
                    if ctype == 'text/html' and not body_content:
                        body_content = part.get_payload(decode=True).decode(part.get_content_charset() or 'utf-8', errors='replace')
                        body_type = "text/html"
                    elif ctype == 'text/plain' and not body_content:
                        body_content = part.get_payload(decode=True).decode(part.get_content_charset() or 'utf-8', errors='replace')
                        body_type = "text/plain"

        else:
            # 멀티파트가 아닌 경우 (단일 텍스트/HTML)
            body_content = msg.get_content()
            body_type = msg.get_content_type()
        
        # 미리보기 텍스트 생성
        preview = ""
        if BeautifulSoup and body_content:
            # HTML 태그 제거하고 텍스트만 추출
            soup = BeautifulSoup(body_content if body_type == 'text/html' else body_content, 'html.parser')
            preview = soup.get_text(separator=' ').strip()[:120] # 앞 120자만
        elif body_content:
             preview = body_content.strip()[:120]

        return {
            'filename': os.path.basename(file_path),
            'path': file_path,
            'subject': subject,
            'from': from_,
            'to': to_,
            'date_str': formatted_date,
            'date_dt': dt_object, # 정렬용
            'preview': preview,
            'body': body_content,
            'body_type': body_type
        }
    except Exception as e:
        print(f"Error parsing {file_path}: {e}")
        return None

# --- 메인 앱 로직 ---
def main():
    # 사이드바 설정
    with st.sidebar:
        st.title("⚙️ 설정")
        # 기본값을 현재 폴더('.')로 설정
        folder_path = st.text_input("📁 EML 폴더 경로", value=".", help="EML 파일이 있는 폴더의 절대 경로 또는 상대 경로를 입력하세요.")
        refresh_btn = st.button("🔄 목록 새로고침", use_container_width=True)
        st.divider()
        st.caption("Made with Streamlit & Python")

    # 세션 상태 관리 (불필요한 재로딩 방지)
    if 'email_data' not in st.session_state:
        st.session_state['email_data'] = []
        st.session_state['needs_load'] = True
    
    if refresh_btn:
        st.session_state['needs_load'] = True

    # EML 파일 로드 및 파싱 로직
    if st.session_state['needs_load'] and folder_path:
        if os.path.isdir(folder_path):
            # 대소문자 구분 없이 .eml 파일 찾기 (Windows 호환성 높임)
            eml_files = []
            for ext in ("*.eml", "*.EML"):
                 eml_files.extend(glob.glob(os.path.join(folder_path, ext)))
            
            data = []
            if eml_files:
                # 스피너 표시
                with st.spinner(f"{len(eml_files)}개의 이메일을 불러오는 중입니다..."):
                    for f_path in eml_files:
                        parsed = parse_eml(f_path)
                        if parsed:
                            data.append(parsed)
                
                # 날짜 기준 내림차순(최신순) 정렬
                data.sort(key=lambda x: x['date_dt'], reverse=True)
            else:
                st.toast("해당 폴더에 .eml 파일이 없습니다.", icon="ℹ️")

            st.session_state['email_data'] = data
            st.session_state['needs_load'] = False # 로드 완료 표시
            # 데이터 로드 후 선택 초기화를 위해 rerun
            st.rerun()
        elif folder_path != ".":
             st.sidebar.error(f"❌ 경로를 찾을 수 없습니다: {folder_path}")

    
    email_list = st.session_state['email_data']

    # --- 메인 레이아웃 (Outlook 스타일 2단 컬럼) ---
    # 왼쪽: 목록 (비율 3.5), 오른쪽: 내용 (비율 6.5)
    col1, col2 = st.columns([3.5, 6.5], gap="small")

    selected_email = None

    # --- 왼쪽 컬럼: 이메일 목록 (Master) ---
    with col1:
        st.subheader(f"받은 편지함 ({len(email_list)})", anchor=False)
        
        if not email_list:
             st.info("표시할 이메일이 없습니다. 폴더 경로를 확인하세요.")
        else:
            # 표시할 데이터프레임 생성
            df = pd.DataFrame(email_list)[['from', 'subject', 'date_str', 'preview']]
            df.columns = ['보낸 사람', '제목', '날짜', '미리보기'] # 헤더 한글화

            # Streamlit 최신 데이터프레임 (선택 기능 활성화)
            selection = st.dataframe(
                df,
                use_container_width=True,
                hide_index=True,
                selection_mode="single-row", # 단일 행 선택 모드
                on_select="rerun", # 선택 시 즉시 앱 재실행하여 오른쪽 창 업데이트
                height=700, # 목록 영역 높이 고정
                column_config={
                    "보낸 사람": st.column_config.TextColumn(width="medium"),
                    "제목": st.column_config.TextColumn(width="large", help="클릭하여 내용 보기"),
                    "날짜": st.column_config.TextColumn(width="small"),
                     "미리보기": st.column_config.TextColumn(width="medium", disabled=True) # 미리보기는 클릭 안되게 시각적 처리
                }
            )

            # 선택된 행의 인덱스 가져오기
            if selection.selection.rows:
                selected_index = selection.selection.rows[0]
                selected_email = email_list[selected_index]

    # --- 오른쪽 컬럼: 선택된 이메일 내용 (Detail) ---
    with col2:
        if selected_email:
            # 1. 헤더 영역 (커스텀 CSS 적용됨)
            st.markdown(f"""
                <div class="email-header-container">
                    <h3 class="email-subject">{selected_email['subject']}</h3>
                    <div class="header-info"><span class="header-label">보낸 사람:</span> {selected_email['from']}</div>
                    <div class="header-info"><span class="header-label">받는 사람:</span> {selected_email['to']}</div>
                    <div class="header-info"><span class="header-label">날짜:</span> {selected_email['date_str']}</div>
                </div>
            """, unsafe_allow_html=True)
            
            # 2. 본문 영역 (스크롤 가능한 컨테이너)
            # st.container에 height를 주어 스크롤 영역 생성
            with st.container(height=600, border=True):
                 # HTML 타입이면 st.html로 렌더링 (스타일 유지)
                if selected_email['body_type'] == 'text/html':
                    st.html(selected_email['body'])
                else:
                    # 일반 텍스트면 st.text로 렌더링 (줄바꿈 유지)
                    st.text(selected_email['body'])
                    
        else:
            # 선택된 이메일이 없을 때 초기 화면
            st.markdown("""
                <div style="display: flex; justify-content: center; align-items: center; height: 70vh; color: #888; flex-direction: column;">
                    <div style="font-size: 4em;">📨</div>
                    <h3>이메일을 선택하세요</h3>
                    <p>왼쪽 목록에서 클릭하면 내용을 볼 수 있습니다.</p>
                </div>
            """, unsafe_allow_html=True)

if __name__ == "__main__":
    main()
