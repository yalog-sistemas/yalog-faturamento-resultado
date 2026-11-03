-- YALOG: module users and section authorization.
create table faturamento_private.user_access (
 company_id text not null references public.empresas(company_id),
 login text not null,
 sections text[] not null check (cardinality(sections)>0 and sections <@ array['overview','storage','transport','costs']::text[]),
 updated_at timestamptz not null default now(),
 updated_by text not null,
 primary key(company_id,login)
);
alter table faturamento_private.user_access enable row level security;
revoke all on faturamento_private.user_access from public,anon,authenticated;

create function faturamento_private.access(p_token text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare s record; central_role text; sections text[]; admin boolean;
begin
 select * into s from faturamento_private.identity(p_token);
 select upper(u.role) into central_role from public.usuarios u where u.company_id=s.company_id and lower(u.login)=lower(s.login);
 admin:=central_role in ('MASTER','SUPER_ADMIN') and upper(s.perfil) in ('MASTER','SUPER_ADMIN');
 select a.sections into sections from faturamento_private.user_access a where a.company_id=s.company_id and a.login=lower(s.login);
 if admin or sections is null then sections:=array['overview','storage','transport','costs'];end if;
 return jsonb_build_object('admin',admin,'profile',case when upper(s.perfil) in ('VISUALIZADOR','CONSULTA','LEITURA','VIEWER') then 'VISUALIZADOR' else 'EXECUTOR' end,'sections',sections);
end $$;

create function faturamento_private.zero_numbers(v jsonb) returns jsonb language plpgsql immutable security invoker set search_path='' as $$
declare r jsonb;
begin
 case jsonb_typeof(v)
 when 'number' then return '0'::jsonb;
 when 'array' then select coalesce(jsonb_agg(faturamento_private.zero_numbers(value)),'[]') into r from jsonb_array_elements(v);return r;
 when 'object' then select coalesce(jsonb_object_agg(key,faturamento_private.zero_numbers(value)),'{}') into r from jsonb_each(v);return r;
 else return v;
 end case;
end $$;

create function faturamento_private.aggregate_inputs(v jsonb,storage boolean,visible boolean) returns jsonb language plpgsql immutable security invoker set search_path='' as $$
declare result jsonb:='{}'; g record; series jsonb; i integer; vals jsonb;
begin
 if storage then
  for g in select * from jsonb_each(v) loop
   series:='[]';for i in 0..11 loop
    select coalesce(sum((a.value->>i)::numeric),0) into vals from jsonb_each(g.value) a where a.key !~ '^20[0-9][0-9]$' and jsonb_typeof(a.value)='array';
    series:=series||jsonb_build_array(case when visible then vals else '0'::jsonb end);
   end loop;
   result:=result||jsonb_build_object(g.key,jsonb_build_object('Faturamento integrado',series,'2026',series,'2025',case when visible then coalesce(g.value->'2025','[]') else faturamento_private.zero_numbers(coalesce(g.value->'2025','[]')) end));
  end loop;
 else
  series:='[]';for i in 0..11 loop
   select coalesce(sum((a.value->>i)::numeric),0) into vals from jsonb_each(v) a where a.key !~ '^20[0-9][0-9]$' and jsonb_typeof(a.value)='array';
   series:=series||jsonb_build_array(case when visible then vals else '0'::jsonb end);
  end loop;
  result:=jsonb_build_object('Faturamento integrado',series,'2025',case when visible then coalesce(v->'2025','[]') else faturamento_private.zero_numbers(coalesce(v->'2025','[]')) end);
 end if;
 return result;
end $$;

create function faturamento_private.summarize_costs(v jsonb,visible boolean) returns jsonb language plpgsql immutable security invoker set search_path='' as $$
declare result jsonb:='{}'; c record; series jsonb;i integer; n numeric;
begin
 for c in select * from jsonb_each(v) loop
  if jsonb_typeof(c.value)='array' then
   series:='[]';for i in 0..11 loop
    select coalesce(sum((r->'values'->>i)::numeric),0) into n from jsonb_array_elements(c.value) r;
    series:=series||jsonb_build_array(case when visible then n else 0 end);
   end loop;
   result:=result||jsonb_build_object(c.key,jsonb_build_array(jsonb_build_object('label','Total da categoria','values',series)));
  end if;
 end loop;
 return result;
end $$;

create function faturamento_private.filter_document(doc jsonb,a jsonb,seed boolean) returns jsonb language plpgsql immutable security invoker set search_path='' as $$
declare d jsonb; inputs jsonb; costs jsonb; revstorage boolean;revtransport boolean; fullstorage boolean;fulltransport boolean; fullcosts boolean;overview boolean; u text;
begin
 if (a->>'admin')::boolean then return doc;end if;
 overview:=(a->'sections')?'overview';fullstorage:=(a->'sections')?'storage';fulltransport:=(a->'sections')?'transport';fullcosts:=(a->'sections')?'costs';
 revstorage:=overview or fullstorage or fullcosts;revtransport:=overview or fulltransport or fullcosts;
 if seed then d:=doc->'ORIGINAL';inputs:=doc->'INPUT_ORIGINAL';costs:=doc->'COST_ORIGINAL';
 else d:=coalesce((doc->>'yalog_fat_allas')::jsonb,'{}');inputs:=coalesce((doc->>'yalog_fat_inputs')::jsonb,'{}');costs:=coalesce((doc->>'yalog_fat_costs')::jsonb,'{}');end if;
 if not revstorage and d->'projectionOverrides'?'storage' then d:=jsonb_set(d,'{projectionOverrides,storage}',faturamento_private.zero_numbers(d->'projectionOverrides'->'storage'));end if;
 if not revtransport and d->'projectionOverrides'?'transport' then d:=jsonb_set(d,'{projectionOverrides,transport}',faturamento_private.zero_numbers(d->'projectionOverrides'->'transport'));end if;
 if not revstorage then d:=jsonb_set(d,'{storage}',faturamento_private.zero_numbers(coalesce(d->'storage','{}')));d:=jsonb_set(d,'{units}',faturamento_private.zero_numbers(coalesce(d->'units','{}')));end if;
 if not revtransport then d:=jsonb_set(d,'{transport}',faturamento_private.zero_numbers(coalesce(d->'transport','{}')));end if;
 if not fullstorage then inputs:=jsonb_set(inputs,'{storageClients}',faturamento_private.aggregate_inputs(coalesce(inputs->'storageClients','{}'),true,revstorage));end if;
 if not fulltransport then inputs:=jsonb_set(inputs,'{transportClients}',faturamento_private.aggregate_inputs(coalesce(inputs->'transportClients','{}'),false,revtransport));end if;
 if not fullcosts then
  foreach u in array array['UBA','UDI','GYN','BSS','transport'] loop
   if costs ? u then costs:=jsonb_set(costs,array[u],faturamento_private.summarize_costs(costs->u,overview));end if;
  end loop;
  costs:=jsonb_set(costs,'{revenueSources}','[]');
  costs:=costs-'transportDreSource';
 end if;
 if seed then
  doc:=doc||jsonb_build_object('ORIGINAL',d,'INPUT_ORIGINAL',inputs,'COST_ORIGINAL',costs);
  if not revstorage then doc:=jsonb_set(doc,'{STORAGE_2024}',faturamento_private.zero_numbers(doc->'STORAGE_2024'));doc:=jsonb_set(doc,'{s24}',faturamento_private.zero_numbers(doc->'s24'));end if;
  if not revtransport then doc:=jsonb_set(doc,'{transport2024}',faturamento_private.zero_numbers(doc->'transport2024'));doc:=jsonb_set(doc,'{TRANSPORT_2025_REFERENCE}',faturamento_private.zero_numbers(doc->'TRANSPORT_2025_REFERENCE'));end if;
  if not fullcosts then doc:=jsonb_set(doc,'{DATA}',faturamento_private.summarize_costs(doc->'DATA',overview));doc:=jsonb_set(doc,'{META}',faturamento_private.zero_numbers(doc->'META'));end if;
 else
  doc:=jsonb_build_object('yalog_fat_allas',d::text,'yalog_fat_inputs',inputs::text,'yalog_fat_costs',costs::text,'yalog_forecast_mode',coalesce(doc->>'yalog_forecast_mode','auto'));
 end if;
 return doc;
end $$;

alter function faturamento_private.load(text) rename to load_full_v1;
alter function faturamento_private.save(text,bigint,jsonb) rename to save_full_v1;
revoke execute on function faturamento_private.load_full_v1(text),faturamento_private.save_full_v1(text,bigint,jsonb) from anon,authenticated;

create function faturamento_private.load(p_token text) returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;a jsonb;
begin
 a:=faturamento_private.access(p_token);r:=faturamento_private.load_full_v1(p_token);
 if r->'storage'='{}'::jsonb then
  r:=jsonb_set(r,'{storage}',jsonb_build_object('yalog_fat_allas',(r->'seed'->'ORIGINAL')::text,'yalog_fat_inputs',(r->'seed'->'INPUT_ORIGINAL')::text,'yalog_fat_costs',(r->'seed'->'COST_ORIGINAL')::text));
 end if;
 return r||jsonb_build_object('access',a,'storage',faturamento_private.filter_document(r->'storage',a,false),'seed',faturamento_private.filter_document(r->'seed',a,true));
end $$;

create function faturamento_private.save(p_token text,p_expected_version bigint,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare s record;a jsonb;base jsonb;d jsonb;nd jsonb;inputs jsonb;ni jsonb; merged jsonb; kind text;prop text; b jsonb;
begin
 select * into s from faturamento_private.identity(p_token);a:=faturamento_private.access(p_token);
 if a->>'profile'='VISUALIZADOR' then raise exception 'Perfil somente leitura' using errcode='42501';end if;
 if jsonb_typeof(p_payload) is distinct from 'object' or octet_length(p_payload::text)>5000000 then raise exception 'Dados inválidos';end if;
 if (a->>'admin')::boolean then return faturamento_private.save_full_v1(p_token,p_expected_version,p_payload);end if;
 select payload into base from faturamento_private.states where company_id=s.company_id for update;
 if base is null then b:=faturamento_private.load_full_v1(p_token)->'seed';base:=jsonb_build_object('yalog_fat_allas',(b->'ORIGINAL')::text,'yalog_fat_inputs',(b->'INPUT_ORIGINAL')::text,'yalog_fat_costs',(b->'COST_ORIGINAL')::text);end if;
 d:=(base->>'yalog_fat_allas')::jsonb;inputs:=(base->>'yalog_fat_inputs')::jsonb;nd:=(p_payload->>'yalog_fat_allas')::jsonb;ni:=(p_payload->>'yalog_fat_inputs')::jsonb;
 if jsonb_typeof(nd) is distinct from 'object' or jsonb_typeof(ni) is distinct from 'object' then raise exception 'Dados de faturamento inválidos';end if;
 foreach kind in array array['storage','transport'] loop
  if (a->'sections') ? kind then
   if jsonb_typeof(nd->kind) is distinct from 'object' or jsonb_typeof(ni->(kind||'Clients')) is distinct from 'object' then raise exception 'Dados da operação inválidos';end if;
   d:=jsonb_set(d,array[kind],nd->kind);inputs:=jsonb_set(inputs,array[kind||'Clients'],ni->(kind||'Clients'));
   if kind='storage' and nd?'units' then d:=jsonb_set(d,'{units}',nd->'units');end if;
   foreach prop in array array['projectionOverrides','projectionStarts','projectionExplicit','inputSynced'] loop
    if nd->prop ? kind then d:=jsonb_set(d,array[prop],coalesce(d->prop,'{}')||jsonb_build_object(kind,nd->prop->kind));end if;
   end loop;
   d:=jsonb_set(d,'{monthClosing}',coalesce(d->'monthClosing','{}')||jsonb_build_object('2026',coalesce(d->'monthClosing'->'2026','{}')||jsonb_build_object(kind,coalesce(nd->'monthClosing'->'2026'->kind,'[]'))));
  end if;
 end loop;
 merged:=base||jsonb_build_object('yalog_fat_allas',d::text,'yalog_fat_inputs',inputs::text);
 if (a->'sections')?'costs' then
  if jsonb_typeof((p_payload->>'yalog_fat_costs')::jsonb) is distinct from 'object' then raise exception 'Custos inválidos';end if;
  merged:=merged||jsonb_build_object('yalog_fat_costs',p_payload->>'yalog_fat_costs');
 end if;
 if (a->'sections')?'storage' and (a->'sections')?'transport' and p_payload?'yalog_forecast_mode' then merged:=merged||jsonb_build_object('yalog_forecast_mode',p_payload->>'yalog_forecast_mode');end if;
 return faturamento_private.save_full_v1(p_token,p_expected_version,merged);
end $$;

create function faturamento_private.users(p_token text) returns jsonb language plpgsql security definer set search_path='' as $$
declare s record;a jsonb;rows jsonb;
begin
 select * into s from faturamento_private.identity(p_token);a:=faturamento_private.access(p_token);
 if not (a->>'admin')::boolean then raise exception 'Somente o MASTER gerencia usuários' using errcode='42501';end if;
 select coalesce(jsonb_agg(jsonb_build_object('login',u.login,'name',u.nome,'central_active',u.ativo,'central_role',u.role,'linked',mu.id is not null,'active',coalesce(mu.ativo,false),'profile',case when upper(mu.perfil) in ('MASTER','SUPER_ADMIN') then 'MASTER' when upper(mu.perfil) in ('VISUALIZADOR','CONSULTA','LEITURA','VIEWER') then 'VISUALIZADOR' else 'EXECUTOR' end,'sections',coalesce(to_jsonb(ua.sections),'["overview","storage","transport","costs"]'::jsonb)) order by u.nome,u.login),'[]') into rows
 from public.usuarios u left join public.module_users mu on mu.company_id=u.company_id and lower(mu.login)=lower(u.login) and mu.modulo='gestodefaturamentoeresultado' left join faturamento_private.user_access ua on ua.company_id=u.company_id and ua.login=lower(u.login) where u.company_id=s.company_id;
 return jsonb_build_object('ok',true,'users',rows);
end $$;

create function faturamento_private.manage_user(p_token text,p_action text,p_login text,p_name text,p_hash text,p_profile text,p_sections text[],p_active boolean) returns jsonb language plpgsql security definer set search_path='' as $$
declare s record;a jsonb;v_login text:=lower(trim(p_login));target record;
begin
 select * into s from faturamento_private.identity(p_token);a:=faturamento_private.access(p_token);
 if not (a->>'admin')::boolean then raise exception 'Somente o MASTER gerencia usuários' using errcode='42501';end if;
 if p_action not in ('CREATE','LINK','UPDATE') or p_action is null or v_login !~ '^[a-z0-9][a-z0-9._-]{2,63}$' or v_login is null or p_profile not in ('VISUALIZADOR','EXECUTOR') or p_profile is null or cardinality(p_sections) is null or cardinality(p_sections)=0 or not p_sections <@ array['overview','storage','transport','costs']::text[] or array_position(p_sections,null) is not null or p_active is null then raise exception 'Preencha usuário, perfil e ao menos uma área válida' using errcode='22023';end if;
 perform pg_advisory_xact_lock(hashtextextended(s.company_id||':fat-users',0));
 select * into target from public.usuarios u where u.company_id=s.company_id and lower(u.login)=v_login;
 if lower(s.login)=v_login or upper(target.role) in ('MASTER','SUPER_ADMIN') then raise exception 'Administradores são gerenciados pela plataforma YALOG' using errcode='42501';end if;
 if p_action='CREATE' then
  if target.id is not null then raise exception 'Login já cadastrado. Selecione vincular usuário existente.' using errcode='23505';end if;
  if length(trim(coalesce(p_name,'')))<2 or length(p_name)>160 or p_hash is null or p_hash !~ '^[a-f0-9]{64}$' then raise exception 'Nome ou senha inválidos' using errcode='22023';end if;
  insert into public.usuarios(company_id,login,nome,senha_hash,role,ativo) values(s.company_id,v_login,trim(p_name),p_hash,'USUARIO',true);
 else
  if target.id is null or not target.ativo then raise exception 'Usuário central inexistente ou inativo';end if;
  if p_action='LINK' and exists(select 1 from public.module_users mu where mu.company_id=s.company_id and lower(mu.login)=v_login and mu.modulo='gestodefaturamentoeresultado') then raise exception 'Usuário já vinculado';end if;
  if p_action='UPDATE' and not exists(select 1 from public.module_users mu where mu.company_id=s.company_id and lower(mu.login)=v_login and mu.modulo='gestodefaturamentoeresultado') then raise exception 'Vínculo inexistente';end if;
 end if;
 update public.module_users mu set perfil=p_profile,ativo=p_active,updated_at=now() where mu.company_id=s.company_id and lower(mu.login)=v_login and mu.modulo='gestodefaturamentoeresultado';
 if not found then insert into public.module_users(company_id,modulo,login,perfil,ativo,created_by) values(s.company_id,'gestodefaturamentoeresultado',v_login,p_profile,p_active,s.login);end if;
 insert into faturamento_private.user_access(company_id,login,sections,updated_by) values(s.company_id,v_login,p_sections,s.login) on conflict(company_id,login) do update set sections=excluded.sections,updated_at=now(),updated_by=excluded.updated_by;
 update public.module_sessions set revoked_at=now() where company_id=s.company_id and lower(module_sessions.login)=v_login and modulo='gestodefaturamentoeresultado' and revoked_at is null;
 insert into public.logs(tipo,detalhe,company_id) values('FATURAMENTO_USUARIO','Usuário '||v_login||': '||p_action||', perfil '||p_profile||', áreas '||array_to_string(p_sections,',')||', ativo '||p_active,s.company_id);
 return jsonb_build_object('ok',true);
end $$;

revoke all on function faturamento_private.access(text),faturamento_private.load(text),faturamento_private.save(text,bigint,jsonb),faturamento_private.users(text),faturamento_private.manage_user(text,text,text,text,text,text,text[],boolean),faturamento_private.zero_numbers(jsonb),faturamento_private.aggregate_inputs(jsonb,boolean,boolean),faturamento_private.summarize_costs(jsonb,boolean),faturamento_private.filter_document(jsonb,jsonb,boolean) from public;
grant execute on function faturamento_private.load(text),faturamento_private.save(text,bigint,jsonb),faturamento_private.users(text),faturamento_private.manage_user(text,text,text,text,text,text,text[],boolean) to anon,authenticated;
create or replace function public.faturamento_carregar(p_token text) returns jsonb language sql security invoker set search_path='' as $$select faturamento_private.load(p_token)$$;
create or replace function public.faturamento_salvar(p_token text,p_expected_version bigint,p_payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select faturamento_private.save(p_token,p_expected_version,p_payload)$$;
create function public.faturamento_usuarios(p_token text) returns jsonb language sql security invoker set search_path='' as $$select faturamento_private.users(p_token)$$;
create function public.faturamento_gerenciar_usuario(p_token text,p_action text,p_login text,p_name text,p_hash text,p_profile text,p_sections text[],p_active boolean) returns jsonb language sql security invoker set search_path='' as $$select faturamento_private.manage_user(p_token,p_action,p_login,p_name,p_hash,p_profile,p_sections,p_active)$$;
revoke all on function public.faturamento_usuarios(text),public.faturamento_gerenciar_usuario(text,text,text,text,text,text,text[],boolean) from public;
grant execute on function public.faturamento_usuarios(text),public.faturamento_gerenciar_usuario(text,text,text,text,text,text,text[],boolean) to anon,authenticated;
