-- =====================================================================
--  마르페 심리상담센터 (marpe.counseling) - Supabase 설정
--  Supabase 대시보드 > SQL Editor > New query 에 전체를 붙여 넣고 [Run]
--  교회 홈페이지 데이터와 섞이지 않도록 모든 이름에 marpe_counseling_ 를 붙였습니다.
--  여러 번 실행해도 안전합니다.
-- =====================================================================

-- 1) 상담사 명단 : 여기에 등록된 이메일로 로그인한 사람만 예약을 보고 고칠 수 있습니다.
create table if not exists public.marpe_counseling_staff (
  email      text primary key,
  name       text,
  created_at timestamptz not null default now()
);

-- 2) 예약
create table if not exists public.marpe_counseling_bookings (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (char_length(name) between 1 and 40),
  phone      text not null default '' check (char_length(phone) <= 30),
  who        text not null default '성인' check (char_length(who) <= 20),
  area       text not null default '기타' check (char_length(area) <= 20),
  booking_date date not null,
  booking_time text not null check (booking_time ~ '^[0-2][0-9]:00$'),
  status     text not null default '대기' check (status in ('대기','확정','완료','취소')),
  memo       text not null default '' check (char_length(memo) <= 300),
  source     text not null default '관리자' check (source in ('홈페이지','관리자')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists marpe_counseling_bookings_date_idx
  on public.marpe_counseling_bookings (booking_date, booking_time);

-- 3) 설정 (카카오톡 채널 링크 등)
create table if not exists public.marpe_counseling_settings (
  key   text primary key,
  value text not null default ''
);
insert into public.marpe_counseling_settings (key, value)
values ('kakao_url', '')
on conflict (key) do nothing;

-- 4) 상담사 여부 확인 함수
create or replace function public.marpe_counseling_is_staff()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.marpe_counseling_staff s
    where lower(s.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;

-- 5) 보안 규칙 (RLS)
alter table public.marpe_counseling_staff    enable row level security;
alter table public.marpe_counseling_bookings enable row level security;
alter table public.marpe_counseling_settings enable row level security;

drop policy if exists "staff read self"       on public.marpe_counseling_staff;
drop policy if exists "staff all bookings"    on public.marpe_counseling_bookings;
drop policy if exists "settings public read"  on public.marpe_counseling_settings;
drop policy if exists "settings staff write"  on public.marpe_counseling_settings;

-- 상담사는 상담사 명단을 볼 수만 있음 (추가·삭제는 SQL Editor에서만)
create policy "staff read self" on public.marpe_counseling_staff
  for select to authenticated using (public.marpe_counseling_is_staff());

-- 예약: 상담사만 읽기·쓰기. 방문자(anon)는 표를 직접 볼 수 없음
create policy "staff all bookings" on public.marpe_counseling_bookings
  for all to authenticated
  using (public.marpe_counseling_is_staff())
  with check (public.marpe_counseling_is_staff());

-- 설정: 누구나 읽기, 상담사만 수정
create policy "settings public read" on public.marpe_counseling_settings
  for select to anon, authenticated using (true);
create policy "settings staff write" on public.marpe_counseling_settings
  for all to authenticated
  using (public.marpe_counseling_is_staff())
  with check (public.marpe_counseling_is_staff());

-- 6) 방문자용: 마감된 시간만 알려주는 함수 (이름·연락처는 절대 내보내지 않음)
create or replace function public.marpe_counseling_taken_slots(from_date date, to_date date)
returns table (slot_date date, slot_time text)
language sql stable security definer
set search_path = public
as $$
  select distinct b.booking_date, b.booking_time
  from public.marpe_counseling_bookings b
  where b.status <> '취소'
    and b.booking_date between from_date and least(to_date, from_date + 60);
$$;

-- 7) 방문자용: 홈페이지에서 예약 신청 (상태 '대기'로만 들어감)
create or replace function public.marpe_counseling_request(
  p_name text, p_phone text, p_who text, p_area text,
  p_date date, p_time text, p_memo text
)
returns text
language plpgsql security definer
set search_path = public
as $$
declare
  kst_today date := (now() at time zone 'Asia/Seoul')::date;
  recent int;
begin
  if coalesce(trim(p_name), '') = '' or coalesce(trim(p_phone), '') = '' then
    raise exception '이름과 연락처를 입력해 주세요.';
  end if;
  if char_length(p_name) > 40 or char_length(p_phone) > 30 or char_length(coalesce(p_memo,'')) > 300 then
    raise exception '입력한 내용이 너무 깁니다.';
  end if;
  if p_date <= kst_today or p_date > kst_today + 30 then
    raise exception '내일부터 30일 안의 날짜만 신청할 수 있어요.';
  end if;
  if extract(dow from p_date) = 0 then
    raise exception '일요일은 운영하지 않습니다.';
  end if;
  if p_time !~ '^[0-2][0-9]:00$' then
    raise exception '시간 형식이 올바르지 않습니다.';
  end if;
  if exists (select 1 from marpe_counseling_bookings
             where booking_date = p_date and booking_time = p_time and status <> '취소') then
    raise exception '방금 다른 분이 예약한 시간이에요. 다른 시간을 골라 주세요.';
  end if;
  -- 같은 번호로 하루 3건 넘게 신청하는 장난 방지
  select count(*) into recent from marpe_counseling_bookings
   where phone = trim(p_phone) and created_at > now() - interval '1 day';
  if recent >= 3 then
    raise exception '신청이 너무 많아요. 전화로 문의해 주세요.';
  end if;

  insert into marpe_counseling_bookings (name, phone, who, area, booking_date, booking_time, status, memo, source)
  values (trim(p_name), trim(p_phone), left(coalesce(p_who,'성인'),20), left(coalesce(p_area,'기타'),20),
          p_date, p_time, '대기', coalesce(trim(p_memo),''), '홈페이지');
  return 'ok';
end;
$$;

-- 8) 권한 정리
revoke all on public.marpe_counseling_staff, public.marpe_counseling_bookings,
              public.marpe_counseling_settings from anon;
grant select on public.marpe_counseling_settings to anon;
grant select, insert, update, delete on public.marpe_counseling_bookings to authenticated;
grant select, insert, update, delete on public.marpe_counseling_settings to authenticated;
grant select on public.marpe_counseling_staff to authenticated;

revoke all on function public.marpe_counseling_taken_slots(date, date) from public;
revoke all on function public.marpe_counseling_request(text,text,text,text,date,text,text) from public;
grant execute on function public.marpe_counseling_taken_slots(date, date) to anon, authenticated;
grant execute on function public.marpe_counseling_request(text,text,text,text,date,text,text) to anon, authenticated;
revoke all on function public.marpe_counseling_is_staff() from public, anon;
grant execute on function public.marpe_counseling_is_staff() to authenticated;

-- =====================================================================
--  9) 상담사 등록 : 아래 이메일을 실제 상담사 이메일로 바꿔서 실행하세요.
--     (Authentication > Users 에서 같은 이메일로 초대도 해야 로그인할 수 있습니다)
-- =====================================================================
insert into public.marpe_counseling_staff (email, name)
values ('pray2002@nate.com', '센터장'), ('marpe.counseling@gmail.com', '관리자')
on conflict (email) do nothing;
