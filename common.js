// 공용 도구 (index.html, admin.html 함께 사용)
(function () {
  const C = window.MARPE_CONFIG || {};
  const WD = ["일", "월", "화", "수", "목", "금", "토"];
  const pad = n => String(n).padStart(2, "0");
  const M = {
    WHO: ["아동", "청소년", "성인", "부부", "가족"],
    AREAS: ["우울·불안", "중독 문제", "학습 동기", "부부 갈등", "가족 관계", "심리검사", "기타"],
    STATUSES: ["대기", "확정", "완료", "취소"],
    WD,
    // 상담 시작 시간 (12시 점심 제외). 평일 10~20시, 토요일 10~16시, 일요일 휴무
    hoursFor(d) { if (d.getDay() === 0) return []; return d.getDay() === 6 ? [10, 11, 13, 14, 15, 16] : [10, 11, 13, 14, 15, 16, 17, 18, 19, 20]; },
    pad,
    hm: h => pad(h) + ":00",
    ymd: d => d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()),
    parse: s => { const [y, m, d] = s.split("-").map(Number); return new Date(y, m - 1, d); },
    korTime: t => { const h = +t.slice(0, 2); return (h < 12 ? "오전 " : "오후 ") + (h > 12 ? h - 12 : h) + "시"; },
    korDate(s) { const d = M.parse(s); return (d.getMonth() + 1) + "월 " + d.getDate() + "일(" + WD[d.getDay()] + ")"; },
    shortDate(s) { const d = M.parse(s); return (d.getMonth() + 1) + "/" + d.getDate() + "(" + WD[d.getDay()] + ")"; },
    mask(n) { n = (n || "").trim(); if (n.length <= 1) return n; if (n.length === 2) return n[0] + "*"; return n[0] + "*".repeat(n.length - 2) + n[n.length - 1]; },
    // Supabase 연결 (키가 아직 없으면 null)
    client() {
      const ok = C.SUPABASE_URL && C.SUPABASE_ANON_KEY && !/여기에/.test(C.SUPABASE_ANON_KEY);
      if (!ok || !window.supabase) return null;
      return window.supabase.createClient(C.SUPABASE_URL, C.SUPABASE_ANON_KEY);
    },
    toast(msg) {
      let t = document.getElementById("toast");
      if (!t) { t = document.createElement("div"); t.id = "toast"; t.className = "toast"; t.setAttribute("role", "status"); document.body.appendChild(t); }
      t.textContent = msg; t.hidden = false; clearTimeout(M._tt); M._tt = setTimeout(() => (t.hidden = true), 2800);
    },
    copy(text, helper) {
      const fallback = () => {
        if (helper) { helper.value = text; helper.hidden = false; helper.focus(); helper.select(); }
        M.toast("자동 복사가 안 돼요. 아래 글을 길게 눌러 복사해 주세요.");
        return false;
      };
      if (navigator.clipboard && window.isSecureContext) {
        return navigator.clipboard.writeText(text).then(() => { if (helper) helper.hidden = true; M.toast("복사했어요. 카카오톡에 붙여 넣어 주세요."); return true; }, fallback);
      }
      return Promise.resolve(fallback());
    }
  };
  window.MARPE = M;
  document.addEventListener("click", e => { const b = e.target.closest("[data-copy]"); if (b) M.copy(b.dataset.copy); });
})();
