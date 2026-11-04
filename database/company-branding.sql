create table if not exists faturamento_private.company_branding(
 company_id text primary key references public.empresas(company_id),display_name text not null check(length(display_name) between 2 and 120),logo_data text,
 updated_at timestamptz not null default now(),updated_by text not null
);
alter table faturamento_private.company_branding enable row level security;
revoke all on faturamento_private.company_branding from public,anon,authenticated;
create or replace function faturamento_private.company_brand(p_token text) returns jsonb language plpgsql security definer set search_path='' as $$
declare s record;r jsonb;
begin
 select * into s from faturamento_private.identity(p_token);perform faturamento_private.assert_password_ready(p_token);
 select jsonb_build_object('display_name',coalesce(b.display_name,nullif(e.nome_fantasia,''),nullif(e.razao_social,''),e.company_id),'logo_data',b.logo_data,'company_id',e.company_id) into r
 from public.empresas e left join faturamento_private.company_branding b on b.company_id=e.company_id where e.company_id=s.company_id;
 return r;
end $$;
create or replace function faturamento_private.save_company_brand(p_token text,p_display_name text,p_logo_data text) returns jsonb language plpgsql security definer set search_path='' as $$
declare s record;a jsonb;name text:=trim(p_display_name);image bytea;mime text;
begin
 select * into s from faturamento_private.identity(p_token);perform faturamento_private.assert_password_ready(p_token);a:=faturamento_private.access(p_token);
 if not coalesce((a->>'admin')::boolean,false) then raise exception 'Somente o MASTER altera a identidade da empresa' using errcode='42501';end if;
 if name is null or length(name)<2 or length(name)>120 then raise exception 'Informe um nome entre 2 e 120 caracteres' using errcode='22023';end if;
 if p_logo_data is not null then
  if length(p_logo_data)>350000 or p_logo_data !~ '^data:image/(png|jpeg|webp);base64,[A-Za-z0-9+/]+={0,2}$' then raise exception 'Logotipo inválido. Use PNG, JPG ou WebP.' using errcode='22023';end if;
  image:=decode(split_part(p_logo_data,',',2),'base64');mime:=split_part(split_part(p_logo_data,';',1),':',2);
  if octet_length(image)>262144 or not ((mime='image/png' and substring(image from 1 for 8)=decode('89504e470d0a1a0a','hex')) or (mime='image/jpeg' and substring(image from 1 for 3)=decode('ffd8ff','hex')) or (mime='image/webp' and substring(image from 1 for 4)=decode('52494646','hex') and substring(image from 9 for 4)=decode('57454250','hex'))) then raise exception 'Formato ou tamanho do logotipo inválido' using errcode='22023';end if;
 end if;
 insert into faturamento_private.company_branding(company_id,display_name,logo_data,updated_by) values(s.company_id,name,p_logo_data,s.login)
 on conflict(company_id) do update set display_name=excluded.display_name,logo_data=excluded.logo_data,updated_by=excluded.updated_by,updated_at=now();
 insert into public.logs(tipo,detalhe,company_id) values('FATURAMENTO_IDENTIDADE_EMPRESA','Identidade visual atualizada por '||s.login,s.company_id);
 return jsonb_build_object('ok',true,'branding',faturamento_private.company_brand(p_token));
end $$;
revoke all on function faturamento_private.company_brand(text),faturamento_private.save_company_brand(text,text,text) from public;
grant execute on function faturamento_private.company_brand(text),faturamento_private.save_company_brand(text,text,text) to anon,authenticated;
create or replace function public.faturamento_identidade_empresa(p_token text) returns jsonb language sql security invoker set search_path='' as $$select faturamento_private.company_brand(p_token)$$;
create or replace function public.faturamento_salvar_identidade(p_token text,p_display_name text,p_logo_data text) returns jsonb language sql security invoker set search_path='' as $$select faturamento_private.save_company_brand(p_token,p_display_name,p_logo_data)$$;
revoke all on function public.faturamento_identidade_empresa(text),public.faturamento_salvar_identidade(text,text,text) from public;
grant execute on function public.faturamento_identidade_empresa(text),public.faturamento_salvar_identidade(text,text,text) to anon,authenticated;
