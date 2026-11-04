-- =====================================================================
--  COFFEEGRAM — 3-QISM: QR VAQTSIZ + QR'LI CHEK
--  02_admin.sql dan KEYIN ishga tushiring. Qayta ishga tushirish xavfsiz.
--
--  - QR endi muddatsiz: ishlatilmaguncha yoki bekor qilinmaguncha amal qiladi
--    (baribir faqat BIR MARTA ishlatiladi).
--  - Kassir QR'ni chekda chop etib, keyingi mijozga o'tishi mumkin —
--    eski QR o'chmaydi, faqat mijoz ekranidan (display) yashiriladi.
-- =====================================================================

alter table public.transactions add column if not exists on_display boolean not null default true;

-- Mavjud ochiq QR'larning muddatini ham uzaytiramiz
update public.transactions set expires_at = created_at + interval '10 years'
 where status = 'pending' and expires_at < created_at + interval '1 day';

create or replace function public.create_transaction(p_amount bigint, p_type text, p_items jsonb default '[]'::jsonb)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare
  v_me     public.profiles;
  v_cafe   public.cafes;
  v_tx     public.transactions;
  v_items  jsonb := '[]'::jsonb;
  v_amount bigint := p_amount;
begin
  select * into v_me from public.profiles where id = auth.uid();
  if v_me.id is null or v_me.role <> 'cashier' or v_me.cafe_id is null then raise exception 'NOT_CASHIER'; end if;
  if not v_me.is_active then raise exception 'BLOCKED'; end if;
  if p_type not in ('cashback', 'spend') then raise exception 'BAD_TYPE'; end if;

  if p_items is not null and jsonb_typeof(p_items) = 'array' and jsonb_array_length(p_items) > 0 then
    select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name, 'price', p.price, 'qty', i.qty)
                              order by p.sort, p.name), '[]'::jsonb),
           coalesce(sum(p.price * i.qty), 0)
      into v_items, v_amount
      from (select (e ->> 'id')::uuid as id, least(99, sum(greatest(1, (e ->> 'qty')::int)))::int as qty
              from jsonb_array_elements(p_items) e group by 1) i
      join public.products p on p.id = i.id and p.is_active;
    if jsonb_array_length(v_items) = 0 then raise exception 'BAD_ITEMS'; end if;
  end if;

  if v_amount is null or v_amount <= 0 or v_amount > 10000000 then raise exception 'BAD_AMOUNT'; end if;

  select * into v_cafe from public.cafes where id = v_me.cafe_id and is_active;
  if v_cafe.id is null then raise exception 'CAFE_INACTIVE'; end if;

  -- oldingi ochiq QR'lar BEKOR QILINMAYDI (mijozda chek bo'lishi mumkin), faqat ekrandan yashiriladi
  update public.transactions set on_display = false
   where cashier_id = v_me.id and status = 'pending' and on_display;

  insert into public.transactions (token, type, amount, cashback_amount, cafe_id, cashier_id, expires_at, items)
  values (encode(gen_random_bytes(24), 'hex'), p_type, v_amount,
          case when p_type = 'cashback' then floor(v_amount * v_cafe.cashback_percent / 100)::bigint else 0 end,
          v_cafe.id, v_me.id, now() + interval '10 years', v_items)
  returning * into v_tx;

  return json_build_object('id', v_tx.id, 'token', v_tx.token, 'type', v_tx.type, 'amount', v_tx.amount,
                           'cashback_amount', v_tx.cashback_amount, 'items', v_tx.items, 'created_at', v_tx.created_at);
end $$;

-- Kassir "Keyingi buyurtma" bosganda: QR amal qilishda davom etadi, lekin mijoz ekranidan yo'qoladi
create or replace function public.cashier_hide_display(p_id uuid)
returns void language sql security definer set search_path = public as $$
  update public.transactions set on_display = false
   where id = p_id and cashier_id = auth.uid();
$$;

create or replace function public.cashier_display()
returns json language plpgsql stable security definer set search_path = public as $$
declare v_me public.profiles; v_cafe public.cafes; v_tx public.transactions; v_u public.profiles;
begin
  select * into v_me from public.profiles where id = auth.uid() and role = 'cashier' and is_active;
  if v_me.id is null then raise exception 'NOT_CASHIER'; end if;
  select * into v_cafe from public.cafes where id = v_me.cafe_id;
  select * into v_tx from public.transactions
   where cashier_id = v_me.id
     and ((status = 'pending' and on_display)
          or (status = 'confirmed' and confirmed_at > now() - interval '12 seconds'))
   order by coalesce(confirmed_at, created_at) desc limit 1;
  select * into v_u from public.profiles where id = v_tx.user_id;
  return json_build_object(
    'cafe_name', v_cafe.name, 'cafe_address', v_cafe.address, 'cashback_percent', v_cafe.cashback_percent,
    'tx', case when v_tx.id is null then null else json_build_object(
      'id', v_tx.id, 'token', v_tx.token, 'type', v_tx.type, 'status', v_tx.status, 'amount', v_tx.amount,
      'cashback_amount', v_tx.cashback_amount, 'balance_used', v_tx.balance_used, 'items', v_tx.items,
      'balance_after', v_tx.balance_after, 'customer_name', v_u.full_name) end);
end $$;

revoke all on function public.cashier_hide_display(uuid) from public, anon;
grant execute on function public.cashier_hide_display(uuid) to authenticated;
revoke all on function public.create_transaction(bigint, text, jsonb) from public, anon;
grant execute on function public.create_transaction(bigint, text, jsonb) to authenticated;
revoke all on function public.cashier_display() from public, anon;
grant execute on function public.cashier_display() to authenticated;
