-- =====================================================================
--  COFFEEGRAM — 5-QISM: ADMIN XODIMNING EMAIL VA PAROLINI O'ZGARTIRADI
--  04_activity.sql dan KEYIN ishga tushiring. Qayta ishga tushirish xavfsiz.
--
--  - Faqat admin chaqira oladi, faqat xodimlar (kassir/admin) uchun.
--  - Parol bazaning o'zida bcrypt bilan shifrlanadi, ochiq holda saqlanmaydi.
--  - Parol o'zgarsa, xodimning barcha qurilmalardagi sessiyalari yopiladi
--    (u yangi parol bilan qayta kirishi kerak bo'ladi).
--  - Har bir o'zgarish jonli jurnalga yoziladi (parolning o'zi yozilmaydi).
-- =====================================================================

create or replace function public.admin_set_credentials(p_user uuid, p_email text default null, p_password text default null)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare
  v_email   text := lower(nullif(trim(coalesce(p_email, '')), ''));
  v_pass    text := nullif(coalesce(p_password, ''), '');
  v_role    text;
  v_old     text;
  v_changes text[] := '{}';
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;

  select role into v_role from public.profiles where id = p_user;
  if v_role is null then raise exception 'NOT_FOUND'; end if;
  if v_role = 'customer' then raise exception 'NOT_STAFF'; end if;

  select email into v_old from auth.users where id = p_user;
  if v_old is null and not exists (select 1 from auth.users where id = p_user) then raise exception 'NOT_FOUND'; end if;
  if v_email is not null and v_email = lower(coalesce(v_old, '')) then v_email := null; end if;
  if v_email is null and v_pass is null then raise exception 'NOTHING_TO_CHANGE'; end if;

  if v_email is not null then
    if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then raise exception 'BAD_EMAIL'; end if;
    if exists (select 1 from auth.users where lower(email) = v_email and id <> p_user) then raise exception 'EMAIL_TAKEN'; end if;

    update auth.users
       set email = v_email, email_confirmed_at = coalesce(email_confirmed_at, now()), updated_at = now()
     where id = p_user;
    update auth.identities
       set identity_data = coalesce(identity_data, '{}'::jsonb) || jsonb_build_object('email', v_email), updated_at = now()
     where user_id = p_user and provider = 'email';
    update public.profiles set email = v_email where id = p_user;
    v_changes := v_changes || ('email: ' || coalesce(v_old, '—') || ' → ' || v_email);
  end if;

  if v_pass is not null then
    if length(v_pass) < 6 then raise exception 'WEAK_PASSWORD'; end if;
    update auth.users
       set encrypted_password = extensions.crypt(v_pass, extensions.gen_salt('bf')), updated_at = now()
     where id = p_user;
    -- eski sessiyalarni yopamiz (jadval bo'lmasa — jim o'tib ketadi)
    begin
      delete from auth.sessions where user_id = p_user;
    exception when undefined_table then null;
    end;
    v_changes := v_changes || 'parol yangilandi'::text;
  end if;

  perform public.log_activity('credentials_changed', null, p_user, null, null, null, null,
                              array_to_string(v_changes, ' · '));
  return json_build_object('email', coalesce(v_email, v_old), 'password_changed', v_pass is not null);
end $$;

revoke all on function public.admin_set_credentials(uuid, text, text) from public, anon;
grant execute on function public.admin_set_credentials(uuid, text, text) to authenticated;
