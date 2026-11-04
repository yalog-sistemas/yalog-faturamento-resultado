CREATE OR REPLACE FUNCTION faturamento_private.assert_subordinate(p_token text, p_login text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare s record;a jsonb;u record;m record;
begin
 select * into s from faturamento_private.identity(p_token);perform faturamento_private.assert_password_ready(p_token);a:=faturamento_private.access(p_token);
 if not coalesce((a->>'manager')::boolean,false) then raise exception 'Somente MASTER e Gestor gerenciam usuários' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended(s.company_id||':fat-users',0));
 select * into u from public.usuarios where company_id=s.company_id and lower(login)=lower(trim(p_login)) for update;
 select * into m from public.module_users where company_id=s.company_id and lower(login)=lower(trim(p_login)) and modulo='gestodefaturamentoeresultado' for update;
 if u.id is null or m.id is null or lower(u.login)=lower(s.login) or upper(u.role) in ('MASTER','SUPER_ADMIN') or upper(m.perfil) in ('MASTER','SUPER_ADMIN') then raise exception 'Usuário protegido ou não vinculado ao módulo' using errcode='42501';end if;
 if not (a->>'admin')::boolean and lower(coalesce(m.created_by,''))<>lower(s.login) then raise exception 'Usuário fora da sua equipe de gestão' using errcode='42501';end if;
 if not (a->>'admin')::boolean and (upper(u.role)='GESTOR' or upper(m.perfil)='GESTOR' or not coalesce((select sections from faturamento_private.user_access where company_id=s.company_id and login=lower(u.login)),array['overview','storage','transport','costs']) <@ array(select jsonb_array_elements_text(a->'sections'))) then raise exception 'Usuário fora da sua hierarquia ou áreas de gestão' using errcode='42501';end if;
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
 if p_action='UPDATE' then perform faturamento_private.assert_subordinate(p_token,v_login);end if;
 if not (a->>'admin')::boolean then
  if p_action='LINK' or (p_action='CREATE' and target.id is not null) then raise exception 'Gestor cadastra somente novos usuários da própria equipe' using errcode='42501';end if;
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
 select coalesce(jsonb_agg(jsonb_build_object('login',u.login,'name',u.nome,'central_active',u.ativo,'password_change_required',coalesce(u.obrigar_troca_senha,false),'central_role',u.role,'managed_by',mu.created_by,'linked',mu.id is not null,'active',coalesce(mu.ativo,false),'profile',case when upper(mu.perfil) in ('MASTER','SUPER_ADMIN') then 'MASTER' when upper(mu.perfil)='GESTOR' then 'GESTOR' when upper(mu.perfil) in ('VISUALIZADOR','CONSULTA','LEITURA','VIEWER') then 'VISUALIZADOR' else 'EXECUTOR' end,'sections',coalesce(to_jsonb(ua.sections),'["overview","storage","transport","costs"]'::jsonb)) order by u.nome,u.login),'[]') into rows
 from public.usuarios u left join public.module_users mu on mu.company_id=u.company_id and lower(mu.login)=lower(u.login) and mu.modulo='gestodefaturamentoeresultado' left join faturamento_private.user_access ua on ua.company_id=u.company_id and ua.login=lower(u.login) where u.company_id=s.company_id and ((a->>'admin')::boolean or (mu.id is not null and lower(coalesce(mu.created_by,''))=lower(s.login) and lower(u.login)<>lower(s.login) and upper(u.role) not in ('MASTER','SUPER_ADMIN','GESTOR') and upper(mu.perfil) not in ('MASTER','SUPER_ADMIN','GESTOR')));
 return jsonb_build_object('ok',true,'users',rows);
end $function$;
