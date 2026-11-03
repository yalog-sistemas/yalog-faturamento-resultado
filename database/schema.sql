
create schema if not exists faturamento_private;
revoke all on schema faturamento_private from public;
grant usage on schema faturamento_private to anon, authenticated;
create table faturamento_private.templates(id text primary key, seed jsonb not null);
create table faturamento_private.company_seeds(company_id text primary key references public.empresas(company_id),seed jsonb not null);
create table faturamento_private.states(company_id text primary key references public.empresas(company_id),payload jsonb not null default '{}',version bigint not null default 0,updated_at timestamptz not null default now(),updated_by text not null);
create table faturamento_private.history(id bigint generated always as identity primary key,company_id text not null,version bigint not null,payload jsonb not null,created_at timestamptz not null default now(),created_by text not null);
create index on faturamento_private.history(company_id,version);
alter table faturamento_private.templates enable row level security;
alter table faturamento_private.company_seeds enable row level security;
alter table faturamento_private.states enable row level security;
alter table faturamento_private.history enable row level security;
revoke all on all tables in schema faturamento_private from public,anon,authenticated;
create function faturamento_private.identity(p_token text) returns table(company_id text,login text,nome text,perfil text) language plpgsql security definer set search_path='' as $$
begin
 if p_token is null or length(p_token)<32 then raise exception 'Sessão inválida ou expirada' using errcode='28000'; end if;
 return query select s.company_id,s.login,u.nome,coalesce(mu.perfil,u.role) from public.module_sessions s join public.usuarios u on u.company_id=s.company_id and lower(u.login)=lower(s.login) and u.ativo join public.empresas e on e.company_id=s.company_id and e.ativo join public.module_users mu on mu.company_id=s.company_id and lower(mu.login)=lower(s.login) and mu.modulo=s.modulo and mu.ativo where s.token=p_token and s.modulo='gestodefaturamentoeresultado' and s.revoked_at is null and s.expires_at>now() and public.usuario_autorizado_modulo(s.company_id,s.login,s.modulo);
 if not found then raise exception 'Acesso não autorizado. Entre novamente pelo YALOG Ecosystem.' using errcode='28000';end if;
end $$;
create function faturamento_private.handoff(p_token text) returns jsonb language plpgsql security definer set search_path='' as $$
declare a record;s record;t text;
begin
 select h.* into a from public.module_access_tokens h join public.ecosystem_sessions es on es.token=h.ecosystem_session_token and es.revoked_at is null and es.expires_at>now() where h.token=p_token and h.modulo='gestodefaturamentoeresultado' and h.used_at is null and h.expires_at>now() for update of h;
 if not found or not public.usuario_autorizado_modulo(a.company_id,a.login,a.modulo) then raise exception 'Acesso inválido, expirado ou bloqueado' using errcode='28000';end if;
 t:=encode(extensions.gen_random_bytes(32),'hex');
 insert into public.module_sessions(token,company_id,login,modulo) values(t,a.company_id,a.login,a.modulo);
 select * into s from faturamento_private.identity(t);
 update public.module_access_tokens set used_at=now() where token=p_token;
 return jsonb_build_object('ok',true,'module_session_token',t,'company_id',s.company_id,'login',s.login,'nome',s.nome,'perfil',s.perfil);
end $$;
create function faturamento_private.load(p_token text) returns jsonb language plpgsql security definer set search_path='' as $$
declare s record;d record;b jsonb;
begin
 select * into s from faturamento_private.identity(p_token);
 select * into d from faturamento_private.states where company_id=s.company_id;
 select seed into b from faturamento_private.company_seeds where company_id=s.company_id;
 if b is null then select seed into b from faturamento_private.templates where id='blank-v53';end if;
 if b is null then raise exception 'Base inicial indisponível';end if;
 return jsonb_build_object('ok',true,'company_id',s.company_id,'login',s.login,'nome',s.nome,'perfil',s.perfil,'version',coalesce(d.version,0),'storage',coalesce(d.payload,'{}'::jsonb),'seed',b);
end $$;
create function faturamento_private.save(p_token text,p_expected_version bigint,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare s record;v bigint;
begin
 select * into s from faturamento_private.identity(p_token);
 if upper(s.perfil) in ('VISUALIZADOR','CONSULTA','LEITURA','VIEWER') then raise exception 'Perfil somente leitura' using errcode='42501';end if;
 if p_expected_version is null or p_expected_version<0 or jsonb_typeof(p_payload) is distinct from 'object' or octet_length(p_payload::text)>5000000 then raise exception 'Dados ou versão inválidos' using errcode='22023';end if;
 if exists(select 1 from jsonb_each(p_payload) kv where kv.key !~ '^yalog_' or jsonb_typeof(kv.value)<>'string') then raise exception 'Formato de dados inválido' using errcode='22023';end if;
 insert into faturamento_private.states(company_id,updated_by) values(s.company_id,s.login) on conflict do nothing;
 select version into v from faturamento_private.states where company_id=s.company_id for update;
 if v<>p_expected_version then return jsonb_build_object('ok',false,'conflict',true,'version',v);end if;
 insert into faturamento_private.history(company_id,version,payload,created_by) select company_id,version,payload,updated_by from faturamento_private.states where company_id=s.company_id;
 update faturamento_private.states set payload=p_payload,version=version+1,updated_at=now(),updated_by=s.login where company_id=s.company_id returning version into v;
 return jsonb_build_object('ok',true,'version',v,'updated_at',now());
end $$;
revoke all on all functions in schema faturamento_private from public;
grant execute on all functions in schema faturamento_private to anon,authenticated;
create function public.faturamento_validar_handoff(p_token text) returns jsonb language sql security invoker set search_path='' as $$select faturamento_private.handoff(p_token)$$;
create function public.faturamento_carregar(p_token text) returns jsonb language sql security invoker set search_path='' as $$select faturamento_private.load(p_token)$$;
create function public.faturamento_salvar(p_token text,p_expected_version bigint,p_payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select faturamento_private.save(p_token,p_expected_version,p_payload)$$;
revoke all on function public.faturamento_validar_handoff(text),public.faturamento_carregar(text),public.faturamento_salvar(text,bigint,jsonb) from public;
grant execute on function public.faturamento_validar_handoff(text),public.faturamento_carregar(text),public.faturamento_salvar(text,bigint,jsonb) to anon,authenticated;
