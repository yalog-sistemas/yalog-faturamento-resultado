'use strict';
(async function(){
 const API='https://pyckcyaojztixsujbylq.supabase.co/rest/v1/rpc/';
 const KEY='sb_publishable_iHBh-BZsjisQc0i09QUDoQ_9mZl1vfk';
 const finishEntry=()=>document.documentElement.classList.remove('yalog-entering');
 const ecosystemURL=()=> 'https://yalog-sistemas.github.io/yalog-ecosystem/'+(identity?.company_id?'?empresa='+encodeURIComponent(identity.company_id):'');
 const sessionKey='yalog_faturamento_session_v1';
 const status=document.getElementById('cloudStatus'),gate=document.getElementById('gateMessage');
 let token='',version=0,identity=null,initialized=false,dirty=false,saving=false,timer=null,conflict=false,store={},lastSaved='',draftKey='',readOnly=false;
 function message(text,error=false){status.textContent=text;status.dataset.level=error?'error':'ok'}
 async function rpc(name,args){const response=await fetch(API+name,{method:'POST',headers:{apikey:KEY,'Content-Type':'application/json'},body:JSON.stringify(args),signal:AbortSignal.timeout(20000)});const body=await response.json();if(!response.ok)throw Object.assign(new Error(body.message||'Falha ao acessar a nuvem.'),{code:body.code});return body}
 function stash(){if(!draftKey)return;try{sessionStorage.setItem(draftKey,JSON.stringify({version,storage:store,pending:dirty}))}catch{message('Não foi possível guardar o rascunho nesta aba. Baixe um backup.',true)}}
 async function persist(){if(!initialized||saving||conflict||readOnly)return;if(!dirty&&JSON.stringify(store)===lastSaved){message('Dados conferidos na nuvem');return}clearTimeout(timer);saving=true;document.getElementById('cloudSave').disabled=true;message('Salvando na nuvem…');const snapshot=JSON.stringify(store);try{const result=await rpc('faturamento_salvar',{p_token:token,p_expected_version:version,p_payload:JSON.parse(snapshot)});if(result.conflict){conflict=true;dirty=true;message('Outra pessoa salvou alterações. Baixe seu backup e reabra o módulo.',true);return}if(!result.ok)throw Error('Salvamento não confirmado');version=result.version;lastSaved=snapshot;dirty=JSON.stringify(store)!==snapshot;stash();message(dirty?'Novas alterações pendentes':'✓ Salvo no Supabase • versão '+version);if(dirty)timer=setTimeout(persist,800)}catch(e){dirty=true;stash();message(e.code==='28000'?'Acesso expirado ou bloqueado. Baixe um backup e entre novamente.':'Sem confirmação na nuvem. Rascunho preservado nesta aba; tente salvar novamente.',true)}finally{saving=false;document.getElementById('cloudSave').disabled=false}}
 function changed(){if(!initialized||readOnly)return;dirty=JSON.stringify(store)!==lastSaved;stash();message('Alterações pendentes de envio');clearTimeout(timer);timer=setTimeout(persist,1000)}
 window.yalogStorage={getItem:key=>Object.hasOwn(store,key)?store[key]:null,setItem(key,value){key=String(key);value=String(value);if(!key.startsWith('yalog_')||(initialized&&readOnly))return;if(store[key]===value)return;store[key]=value;changed()},removeItem(key){if(initialized&&readOnly)return;delete store[key];changed()},clear(){if(initialized&&readOnly)return;store={};changed()},key:i=>Object.keys(store)[i]??null,get length(){return Object.keys(store).length}};
 function flushEditors(){if(readOnly)return true;if(document.getElementById('inputModal')?.classList.contains('open')&&window.saveInputs&&window.saveInputs()===false)return false;if(window.saveCosts&&window.yalogCostsDirty&&window.saveCosts()===false)return false;return true}
 document.getElementById('cloudSave').onclick=async()=>{if(flushEditors())await persist()};
 document.getElementById('cloudBackup').onclick=()=>{if(!readOnly&&!flushEditors())return;const blob=new Blob([JSON.stringify({format:'yalog-faturamento-v1',company_id:identity.company_id,version,storage:store},null,2)],{type:'application/json'});const a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download='YALOG_Faturamento_'+identity.company_id+'.json';a.click();setTimeout(()=>URL.revokeObjectURL(a.href),1000)};
 document.getElementById('cloudExit').onclick=()=>{if((dirty||window.yalogCostsDirty)&&!confirm('Há alterações pendentes. Baixe um backup ou salve antes de sair. Sair mesmo assim?'))return;sessionStorage.removeItem(sessionKey);document.documentElement.classList.add('yalog-entering');location.replace(ecosystemURL())};
 window.addEventListener('beforeunload',e=>{if(dirty||window.yalogCostsDirty){stash();e.preventDefault();e.returnValue=''}});
 async function beforePasswordChange(){if(!initialized)return;if(!flushEditors())throw Error('Conclua o salvamento dos lançamentos antes de alterar a senha.');if(dirty||saving){await persist();if(dirty||saving||conflict)throw Error('Aguarde a confirmação do salvamento ou baixe um backup antes de alterar a senha.')}}
 function passwordChanged(){sessionStorage.removeItem(sessionKey);token='';initialized=false;clearTimeout(timer);const settings=document.getElementById('yalogUserSettings');if(settings?.open)settings.close();document.body.classList.remove('yalog-authorized');document.getElementById('cloudGate').hidden=false;gate.textContent='Senha alterada com sucesso. Entre novamente no YALOG Ecosystem com sua nova senha.';const link=document.querySelector('#cloudGate a');if(link)link.href='https://yalog-sistemas.github.io/yalog-ecosystem/?empresa='+encodeURIComponent(identity.company_id)}
 function passwordExit(){sessionStorage.removeItem(sessionKey);token='';initialized=false;document.getElementById('cloudGate').hidden=false;gate.textContent='Entre novamente pelo Ecosystem para continuar.'}
 try{
  const params=new URLSearchParams(location.search),handoff=params.get('handoff');if(handoff){params.delete('handoff');history.replaceState({},'',location.pathname+(params.size?'?'+params:'')+location.hash);const session=await rpc('faturamento_validar_handoff',{p_token:handoff});token=session.module_session_token;sessionStorage.setItem(sessionKey,token)}else token=sessionStorage.getItem(sessionKey)||'';
  if(!token){finishEntry();gate.textContent='Acesse este módulo pelo YALOG Ecosystem com uma empresa e um usuário autorizados.';return}
  const loaded=await rpc('faturamento_carregar',{p_token:token});identity=loaded;if(loaded.password_change_required){finishEntry();gate.textContent='Sua senha temporária precisa ser alterada para acessar o módulo.';window.openYalogPasswordSettings({identity:loaded,rpc,token:()=>token,beforeChange:beforePasswordChange,onChanged:passwordChanged,onExit:passwordExit,force:true});return}window.YALOG_COMPANY_BRAND=await rpc('faturamento_identidade_empresa',{p_token:token});readOnly=['VISUALIZADOR','CONSULTA','LEITURA','VIEWER'].includes(String(loaded.access?.profile||loaded.perfil).trim().toUpperCase());version=loaded.version;store={...loaded.storage};lastSaved=JSON.stringify(store);draftKey='yalog_faturamento_draft:'+loaded.company_id+':'+loaded.login;
  const draft=JSON.parse(sessionStorage.getItem(draftKey)||'null');if(!readOnly&&draft?.pending&&draft.version===version&&confirm('Encontramos um rascunho não enviado nesta aba. Deseja recuperá-lo?')){store=draft.storage;dirty=true}
  window.YALOG_BOOT={seed:loaded.seed};
  let scriptError=null;const capture=e=>{scriptError=e.error||Error(e.message)};window.addEventListener('error',capture);
  const sources=[...document.querySelectorAll('script[type="application/yalog"]')];if(sources.length!==21)throw Error('Publicação incompleta. Atualize a página.');
  for(const source of sources){const s=document.createElement('script');s.dataset.yalogSource=source.id||'core';s.textContent=source.textContent;document.body.appendChild(s);if(scriptError)throw scriptError;source.dataset.executed='true'}
  window.YALOG_RUNTIME_RELEASE=document.querySelector('meta[name="yalog-release"]').content;
  window.removeEventListener('error',capture);
  document.getElementById('cloudIdentity').textContent='YALOG • '+loaded.company_id+' • '+(loaded.nome||loaded.login)+' • '+window.YALOG_RUNTIME_RELEASE;
  document.getElementById('cloudGate').hidden=true;document.body.classList.add('yalog-authorized');
  if(typeof window.render!=='function')throw Error('Interface não inicializada.');
  window.render();
  if(typeof window.installYalogAccess!=='function')throw Error('Configurações indisponíveis. Atualize a página.');
  window.installYalogAccess({identity:loaded,rpc,token:()=>token,notify:message,beforePasswordChange,onPasswordChanged:passwordChanged,onPasswordExit:passwordExit});
  requestAnimationFrame(()=>window.dispatchEvent(new Event('resize')));
  window.installYalogCompanyBranding?.({identity:loaded,rpc,token:()=>token,branding:window.YALOG_COMPANY_BRAND});
  window.installYalogCostEntry?.();
  window.installYalogCostAccountEditor?.({identity:loaded});
  initialized=true;finishEntry();
  if(readOnly){document.getElementById('cloudSave').disabled=true;dirty=false;message('Consulta • dados carregados do Supabase');}
  const initial=JSON.stringify(store);if(!readOnly&&(version===0||dirty||initial!==lastSaved)){dirty=true;stash();await persist()}else message('✓ Dados carregados do Supabase • versão '+version);
  setInterval(async()=>{if(!readOnly&&(dirty||saving||window.yalogCostsDirty))return;try{const remote=await rpc('faturamento_carregar',{p_token:token});if(remote.version!==version){message('Há uma versão mais recente na nuvem. Reabra o módulo para atualizar.',true);conflict=true}}catch(e){if(e.code==='28000'){initialized=false;document.body.classList.remove('yalog-authorized');document.getElementById('cloudGate').hidden=false;gate.textContent='Seu acesso expirou ou foi bloqueado. Entre novamente pelo Ecosystem.'}}},60000);
 }catch(e){finishEntry();document.body.classList.remove('yalog-authorized');document.getElementById('cloudGate').hidden=false;gate.textContent='Não foi possível abrir o módulo: '+e.message;console.error('YALOG Faturamento:',e.message)}
})();
