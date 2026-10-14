-- Slike artikala. Katalog slika je zajednički za sve kafiće i puni ga prodavac
-- (supabase/slike.sql); gazda u admin panelu samo bira sliku za svoj artikal.
-- Slike su male i čuvaju se u bazi kao base64, da ih telefon dobije istim putem kao smjenu.

create table public.catalog_images (
  id uuid primary key default gen_random_uuid(),
  name text not null unique check (length(trim(name)) > 0),
  mime text not null,
  data text not null,
  created_at timestamptz not null default now()
);

alter table public.items
  add column image_id uuid references public.catalog_images (id) on delete set null;

alter table public.catalog_images enable row level security;

-- Katalog vidi svaki prijavljeni gazda; mijenja ga samo prodavac kroz SQL Editor.
create policy catalog_images_select on public.catalog_images
  for select to authenticated using (true);

revoke all on public.catalog_images from anon, authenticated;
grant select on public.catalog_images to authenticated;
grant update (image_id) on public.items to authenticated;

-- Smjena koju telefon čita sada nosi i sliku svakog artikla.
create or replace function private.shift_json(p_shift_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select to_jsonb(s) || jsonb_build_object(
    'shift_lines', coalesce((
      select jsonb_agg(
        to_jsonb(l) || jsonb_build_object('image_id', i.image_id)
        order by l.sort_order, l.item_name)
      from public.shift_lines l
      join public.items i on i.id = l.item_id
      where l.shift_id = s.id), '[]'::jsonb),
    'receipts', coalesce((
      select jsonb_agg(
        to_jsonb(r) || jsonb_build_object('receipt_lines', coalesce((
          select jsonb_agg(to_jsonb(rl))
          from public.receipt_lines rl where rl.receipt_id = r.id), '[]'::jsonb))
        order by r.created_at)
      from public.receipts r where r.shift_id = s.id), '[]'::jsonb),
    'expenses', coalesce((
      select jsonb_agg(to_jsonb(e) order by e.created_at)
      from public.expenses e where e.shift_id = s.id), '[]'::jsonb)
  )
  from public.shifts s
  where s.id = p_shift_id;
$$;

-- Telefon traži slike koje još nema; čuva ih kod sebe, pa rade i bez interneta.
create function public.fetch_images(p_token text, p_ids uuid[])
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_session(p_token);
  if coalesce(array_length(p_ids, 1), 0) > 200 then
    raise exception 'Previše slika u jednom zahtjevu' using errcode = '22023';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'data', c.data))
    from public.catalog_images c
    where c.id = any (p_ids)
  ), '[]'::jsonb);
end;
$$;

revoke execute on function public.fetch_images(text, uuid[]) from public;
grant execute on function public.fetch_images(text, uuid[]) to anon, authenticated;
