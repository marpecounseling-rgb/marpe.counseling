# marpe.counseling

마르페 심리상담센터 홈페이지 (정적 사이트 + Supabase)

- `index.html` 공개 홈페이지 · 예약 신청 · 카톡 보내기
- `admin.html` 상담사 예약 관리 (Supabase 이메일 로그인)
- `config.js` Supabase URL / anon 키 (service_role 키 금지)
- `supabase-setup.sql` 표·보안 규칙 (`marpe_counseling_*`) — SQL Editor에서 1회 실행

배포: Netlify 사이트 이름 `marpe-counseling`, 빌드 설정 없음.
