create function faturamento_private.assert_subordinate(p_token text,p_login text) returns void language plpgsql security definer set search_path='' as $$
declare s record;a jsonb;u record;m record;
begin
 select * into s from faturamento_private.identity(p_token);perform faturamento_private.assert_password_ready(p_token);a:=faturamento_private.access(p_token);
 if not coalesce((a->>'manager')::boolean,false) then raise exception 'Somente MASTER e Gestor gerenciam usuários' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended(s.company_id||':fat-users',0));
 select * into u from public.usuarios where company_id=s.company_id and lower(login)=lower(trim(p_login)) for update;
 select * into m from public.module_users where company_id=s.company_id and lower(login)=lower(trim(p_login)) and modulo='gestodefaturamentoeresultado' for update;
 if u.id is null or m.id is null or lower(u.login)=lower(s.login) or upper(u.role) in ('MASTER','SUPER_ADMIN') or upper(m.perfil) in ('MASTER','SUPER_ADMIN') then raise exception 'Usuário protegido ou não vinculado ao módulo' using errcode='42501';end if;
 if not (a->>'admin')::boolean and (upper(u.role)='GESTOR' or upper(m.perfil)='GESTOR' or not coalesce((select sections from faturamento_private.user_access where company_id=s.company_id and login=lower(u.login)),array['overview','storage','transport','costs']) <@ array(select jsonb_array_elements_text(a->'sections'))) then raise exception 'Usuário fora da sua hierarquia ou áreas de gestão' using errcode='42501';end if;
end $$;
revoke all on function faturamento_private.assert_subordinate(text,text) from public;
create or replace function faturamento_private.reset_password(p_token text,p_login text,p_new_hash text) returns jsonb language plpgsql security definer set search_path='' as $$
declare s record;a jsonb;u record;
begin
 select * into s from faturamento_private.identity(p_token);perform faturamento_private.assert_password_ready(p_token);a:=faturamento_private.access(p_token);
 perform faturamento_private.assert_subordinate(p_token,p_login);
 if p_new_hash is null or p_new_hash !~ '^[a-f0-9]{64}$' then raise exception 'Senha inválida' using errcode='22023';end if;
 select * into u from public.usuarios target where target.company_id=s.company_id and lower(target.login)=lower(trim(p_login)) for update;
 if u.id is null or lower(u.login)=lower(s.login) or upper(u.role) in ('MASTER','SUPER_ADMIN') or exists(select 1 from public.module_users mu where mu.company_id=s.company_id and lower(mu.login)=lower(u.login) and mu.modulo='gestodefaturamentoeresultado' and upper(mu.perfil) in ('MASTER','SUPER_ADMIN')) then raise exception 'Selecione um usuário abaixo do perfil MASTER' using errcode='42501';end if;
 if not exists(select 1 from public.module_users mu where mu.company_id=s.company_id and lower(mu.login)=lower(u.login) and mu.modulo='gestodefaturamentoeresultado') then raise exception 'Usuário não vinculado a este módulo' using errcode='42501';end if;
 if u.senha_hash=p_new_hash then raise exception 'A nova senha deve ser diferente da atual';end if;
 update public.usuarios set senha_hash=p_new_hash,obrigar_troca_senha=true,updated_at=now() where id=u.id;
 update public.module_sessions set revoked_at=now() where company_id=s.company_id and lower(login)=lower(u.login) and revoked_at is null;
 update public.ecosystem_sessions set revoked_at=now() where company_id=s.company_id and lower(login)=lower(u.login) and revoked_at is null;
 update public.module_access_tokens set used_at=coalesce(used_at,now()) where company_id=s.company_id and lower(login)=lower(u.login);
 insert into public.logs(tipo,detalhe,company_id) values('FATURAMENTO_SENHA_REDEFINIDA','Gestor/MASTER '||s.login||' redefiniu a senha de '||u.login||'. Troca obrigatória no próximo acesso e sessões anteriores encerradas.',s.company_id);
 return jsonb_build_object('ok',true,'password_change_required',true);
end $$;

create function faturamento_private.user_action(p_token text,p_action text,p_login text) returns jsonb language plpgsql security definer set search_path='' as $$
declare s record;v_login text:=lower(trim(p_login));
begin
 perform faturamento_private.assert_subordinate(p_token,p_login);select * into s from faturamento_private.identity(p_token);
 if p_action is null or p_action not in ('BLOCK','UNBLOCK','DELETE') then raise exception 'Ação inválida' using errcode='22023';end if;
 if p_action='UNBLOCK' and not exists(select 1 from public.usuarios where company_id=s.company_id and lower(login)=v_login and ativo) then raise exception 'Usuário inativo na plataforma YALOG';end if;
 if p_action='DELETE' then
  delete from public.module_users where company_id=s.company_id and lower(login)=v_login and modulo='gestodefaturamentoeresultado';
  delete from faturamento_private.user_access where company_id=s.company_id and login=v_login;
 else
  update public.module_users set ativo=(p_action='UNBLOCK'),updated_at=now() where company_id=s.company_id and lower(login)=v_login and modulo='gestodefaturamentoeresultado';
 end if;
 update public.module_sessions set revoked_at=now() where company_id=s.company_id and lower(login)=v_login and modulo='gestodefaturamentoeresultado' and revoked_at is null;
 update public.module_access_tokens set used_at=coalesce(used_at,now()) where company_id=s.company_id and lower(login)=v_login and modulo='gestodefaturamentoeresultado';
 insert into public.logs(tipo,detalhe,company_id) values('FATURAMENTO_USUARIO',s.login||': '||p_action||' acesso ao módulo de '||v_login,s.company_id);
 return jsonb_build_object('ok',true);
end $$;
revoke all on function faturamento_private.user_action(text,text,text) from public;
grant execute on function faturamento_private.user_action(text,text,text) to anon,authenticated;
create function public.faturamento_acao_usuario(p_token text,p_action text,p_login text) returns jsonb language sql security invoker set search_path='' as $$select faturamento_private.user_action(p_token,p_action,p_login)$$;
revoke all on function public.faturamento_acao_usuario(text,text,text) from public;
grant execute on function public.faturamento_acao_usuario(text,text,text) to anon,authenticated;
