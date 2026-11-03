create function faturamento_private.assert_password_ready(p_token text) returns void language plpgsql security definer set search_path='' as $$
declare s record;
begin
 select * into s from faturamento_private.identity(p_token);
 if exists(select 1 from public.usuarios u where u.company_id=s.company_id and lower(u.login)=lower(s.login) and coalesce(u.obrigar_troca_senha,false)) then raise exception 'Altere sua senha para continuar' using errcode='42501';end if;
end $$;

create function faturamento_private.change_password(p_token text,p_current_hash text,p_new_hash text) returns jsonb language plpgsql security definer set search_path='' as $$
declare s record;u record;
begin
 select * into s from faturamento_private.identity(p_token);
 select * into u from public.usuarios a where a.company_id=s.company_id and lower(a.login)=lower(s.login) for update;
 if p_current_hash is null or u.senha_hash is distinct from p_current_hash then raise exception 'Senha atual incorreta' using errcode='28000';end if;
 if p_new_hash is null or p_new_hash !~ '^[a-f0-9]{64}$' or p_new_hash=p_current_hash then raise exception 'Informe uma senha nova diferente da atual' using errcode='22023';end if;
 update public.usuarios set senha_hash=p_new_hash,obrigar_troca_senha=false,updated_at=now() where id=u.id;
 update public.module_sessions set revoked_at=now() where company_id=s.company_id and lower(login)=lower(s.login) and revoked_at is null;
 update public.ecosystem_sessions set revoked_at=now() where company_id=s.company_id and lower(login)=lower(s.login) and revoked_at is null;
 update public.module_access_tokens set used_at=coalesce(used_at,now()) where company_id=s.company_id and lower(login)=lower(s.login);
 insert into public.logs(tipo,detalhe,company_id) values('FATURAMENTO_SENHA_ALTERADA','Própria senha alterada pelo usuário '||s.login||'. Sessões anteriores encerradas.',s.company_id);
 return jsonb_build_object('ok',true,'reauthenticate',true);
end $$;

create function faturamento_private.reset_password(p_token text,p_login text,p_new_hash text) returns jsonb language plpgsql security definer set search_path='' as $$
declare s record;a jsonb;u record;
begin
 select * into s from faturamento_private.identity(p_token);perform faturamento_private.assert_password_ready(p_token);a:=faturamento_private.access(p_token);
 if not (a->>'admin')::boolean then raise exception 'Somente o MASTER redefine senhas' using errcode='42501';end if;
 if p_new_hash is null or p_new_hash !~ '^[a-f0-9]{64}$' then raise exception 'Senha inválida' using errcode='22023';end if;
 select * into u from public.usuarios target where target.company_id=s.company_id and lower(target.login)=lower(trim(p_login)) for update;
 if u.id is null or lower(u.login)=lower(s.login) or upper(u.role) in ('MASTER','SUPER_ADMIN') or exists(select 1 from public.module_users mu where mu.company_id=s.company_id and lower(mu.login)=lower(u.login) and mu.modulo='gestodefaturamentoeresultado' and upper(mu.perfil) in ('MASTER','SUPER_ADMIN')) then raise exception 'Selecione um usuário abaixo do perfil MASTER' using errcode='42501';end if;
 if not exists(select 1 from public.module_users mu where mu.company_id=s.company_id and lower(mu.login)=lower(u.login) and mu.modulo='gestodefaturamentoeresultado') then raise exception 'Usuário não vinculado a este módulo' using errcode='42501';end if;
 if u.senha_hash=p_new_hash then raise exception 'A nova senha deve ser diferente da atual';end if;
 update public.usuarios set senha_hash=p_new_hash,obrigar_troca_senha=true,updated_at=now() where id=u.id;
 update public.module_sessions set revoked_at=now() where company_id=s.company_id and lower(login)=lower(u.login) and revoked_at is null;
 update public.ecosystem_sessions set revoked_at=now() where company_id=s.company_id and lower(login)=lower(u.login) and revoked_at is null;
 update public.module_access_tokens set used_at=coalesce(used_at,now()) where company_id=s.company_id and lower(login)=lower(u.login);
 insert into public.logs(tipo,detalhe,company_id) values('FATURAMENTO_SENHA_REDEFINIDA','MASTER '||s.login||' redefiniu a senha de '||u.login||'. Troca obrigatória no próximo acesso e sessões anteriores encerradas.',s.company_id);
 return jsonb_build_object('ok',true,'password_change_required',true);
end $$;

revoke all on function faturamento_private.assert_password_ready(text),faturamento_private.change_password(text,text,text),faturamento_private.reset_password(text,text,text) from public;
grant execute on function faturamento_private.change_password(text,text,text),faturamento_private.reset_password(text,text,text) to anon,authenticated;
create function public.faturamento_alterar_senha(p_token text,p_current_hash text,p_new_hash text) returns jsonb language sql security invoker set search_path='' as $$select faturamento_private.change_password(p_token,p_current_hash,p_new_hash)$$;
create function public.faturamento_redefinir_senha(p_token text,p_login text,p_new_hash text) returns jsonb language sql security invoker set search_path='' as $$select faturamento_private.reset_password(p_token,p_login,p_new_hash)$$;
revoke all on function public.faturamento_alterar_senha(text,text,text),public.faturamento_redefinir_senha(text,text,text) from public;
grant execute on function public.faturamento_alterar_senha(text,text,text),public.faturamento_redefinir_senha(text,text,text) to anon,authenticated;

CREATE OR REPLACE FUNCTION faturamento_private.access(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare s record; central_role text; sections text[]; admin boolean;
begin
 select * into s from faturamento_private.identity(p_token);
 select upper(u.role) into central_role from public.usuarios u where u.company_id=s.company_id and lower(u.login)=lower(s.login);
 admin:=central_role in ('MASTER','SUPER_ADMIN') and upper(s.perfil) in ('MASTER','SUPER_ADMIN');
 select a.sections into sections from faturamento_private.user_access a where a.company_id=s.company_id and a.login=lower(s.login);
 if admin or sections is null then sections:=array['overview','storage','transport','costs'];end if;
 return jsonb_build_object('admin',admin,'profile',case when upper(s.perfil) in ('VISUALIZADOR','CONSULTA','LEITURA','VIEWER') then 'VISUALIZADOR' when upper(s.perfil)='GESTOR' then 'GESTOR' else 'EXECUTOR' end,'sections',sections,'manager',admin or upper(s.perfil)='GESTOR');
end $function$;
CREATE OR REPLACE FUNCTION faturamento_private.load(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r jsonb;a jsonb;s record;
begin
 a:=faturamento_private.access(p_token);select * into s from faturamento_private.identity(p_token);
 if exists(select 1 from public.usuarios u where u.company_id=s.company_id and lower(u.login)=lower(s.login) and coalesce(u.obrigar_troca_senha,false)) then return jsonb_build_object('ok',true,'company_id',s.company_id,'login',s.login,'nome',s.nome,'perfil',s.perfil,'access',a,'password_change_required',true);end if;
 r:=faturamento_private.load_full_v1(p_token);
 if r->'storage'='{}'::jsonb then
  r:=jsonb_set(r,'{storage}',jsonb_build_object('yalog_fat_allas',(r->'seed'->'ORIGINAL')::text,'yalog_fat_inputs',(r->'seed'->'INPUT_ORIGINAL')::text,'yalog_fat_costs',(r->'seed'->'COST_ORIGINAL')::text));
 end if;
 return r||jsonb_build_object('password_change_required',false,'access',a,'storage',faturamento_private.filter_document(r->'storage',a,false),'seed',faturamento_private.filter_document(r->'seed',a,true));
end $function$;
CREATE OR REPLACE FUNCTION faturamento_private.manage_user(p_token text, p_action text, p_login text, p_name text, p_hash text, p_profile text, p_sections text[], p_active boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare s record;a jsonb;v_login text:=lower(trim(p_login));target record;
begin
 select * into s from faturamento_private.identity(p_token);a:=faturamento_private.access(p_token);
 perform faturamento_private.assert_password_ready(p_token);
 if not (a->>'manager')::boolean then raise exception 'Somente MASTER e Gestor gerenciam usuários' using errcode='42501';end if;
 if p_action not in ('CREATE','LINK','UPDATE') or p_action is null or v_login !~ '^[a-z0-9][a-z0-9._-]{2,63}$' or v_login is null or p_profile not in ('VISUALIZADOR','EXECUTOR','GESTOR') or p_profile is null or cardinality(p_sections) is null or cardinality(p_sections)=0 or not p_sections <@ array['overview','storage','transport','costs']::text[] or array_position(p_sections,null) is not null or p_active is null then raise exception 'Preencha usuário, perfil e ao menos uma área válida' using errcode='22023';end if;
 perform pg_advisory_xact_lock(hashtextextended(s.company_id||':fat-users',0));
 select * into target from public.usuarios u where u.company_id=s.company_id and lower(u.login)=v_login;
 if lower(s.login)=v_login or upper(target.role) in ('MASTER','SUPER_ADMIN') then raise exception 'Administradores são gerenciados pela plataforma YALOG' using errcode='42501';end if;
 if not (a->>'admin')::boolean then
  if p_profile='GESTOR' or not p_sections <@ array(select jsonb_array_elements_text(a->'sections')) then raise exception 'Gestor só gerencia Visualizadores e Executores nas próprias áreas' using errcode='42501';end if;
  if upper(target.role)='GESTOR' or exists(select 1 from public.module_users mu where mu.company_id=s.company_id and lower(mu.login)=v_login and mu.modulo='gestodefaturamentoeresultado' and upper(mu.perfil) in ('GESTOR','MASTER','SUPER_ADMIN')) then raise exception 'Gestores e administradores são gerenciados pelo MASTER' using errcode='42501';end if;
  if exists(select 1 from public.module_users mu where mu.company_id=s.company_id and lower(mu.login)=v_login and mu.modulo='gestodefaturamentoeresultado') and not coalesce((select ua.sections from faturamento_private.user_access ua where ua.company_id=s.company_id and ua.login=v_login),array['overview','storage','transport','costs']) <@ array(select jsonb_array_elements_text(a->'sections')) then raise exception 'Usuário possui áreas fora da gestão deste Gestor' using errcode='42501';end if;
 end if;
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
end $function$;
CREATE OR REPLACE FUNCTION faturamento_private.save(p_token text, p_expected_version bigint, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare s record;a jsonb;base jsonb;d jsonb;nd jsonb;inputs jsonb;ni jsonb; merged jsonb; kind text;prop text; b jsonb;
begin
 select * into s from faturamento_private.identity(p_token);perform faturamento_private.assert_password_ready(p_token);a:=faturamento_private.access(p_token);
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
end $function$;
CREATE OR REPLACE FUNCTION faturamento_private.users(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare s record;a jsonb;rows jsonb;
begin
 select * into s from faturamento_private.identity(p_token);a:=faturamento_private.access(p_token);
 perform faturamento_private.assert_password_ready(p_token);
 if not (a->>'manager')::boolean then raise exception 'Somente MASTER e Gestor gerenciam usuários' using errcode='42501';end if;
 select coalesce(jsonb_agg(jsonb_build_object('login',u.login,'name',u.nome,'central_active',u.ativo,'password_change_required',coalesce(u.obrigar_troca_senha,false),'central_role',u.role,'linked',mu.id is not null,'active',coalesce(mu.ativo,false),'profile',case when upper(mu.perfil) in ('MASTER','SUPER_ADMIN') then 'MASTER' when upper(mu.perfil)='GESTOR' then 'GESTOR' when upper(mu.perfil) in ('VISUALIZADOR','CONSULTA','LEITURA','VIEWER') then 'VISUALIZADOR' else 'EXECUTOR' end,'sections',coalesce(to_jsonb(ua.sections),'["overview","storage","transport","costs"]'::jsonb)) order by u.nome,u.login),'[]') into rows
 from public.usuarios u left join public.module_users mu on mu.company_id=u.company_id and lower(mu.login)=lower(u.login) and mu.modulo='gestodefaturamentoeresultado' left join faturamento_private.user_access ua on ua.company_id=u.company_id and ua.login=lower(u.login) where u.company_id=s.company_id;
 return jsonb_build_object('ok',true,'users',rows);
end $function$;