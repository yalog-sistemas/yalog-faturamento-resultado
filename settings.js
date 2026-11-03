'use strict';
window.installYalogAccess = function installYalogAccess({identity, rpc, token, notify, beforePasswordChange, onPasswordChanged, onPasswordExit}) {
  const access=identity.access;
  if(!access||!Array.isArray(access.sections))throw Error('Permissões indisponíveis. Entre novamente.');
  const labels={overview:'Visão Geral',storage:'Armazenagem',transport:'Transporte',costs:'Custos e Despesas'};
  const can=section=>access.admin||access.sections.includes(section);
  const execute=section=>access.profile!=='VISUALIZADOR'&&can(section);
  const deny=()=>{notify('Seu perfil não permite esta ação.',true);return false};
  const guard=(name,test)=>{const base=window[name];if(typeof base==='function')window[name]=function(...args){return test(...args)?base.apply(this,args):deny()}};
  const originalGo=window.go;
  window.go=function(tab){return can(tab)?originalGo.call(this,tab):deny()};
  guard('openInput',kind=>can(kind));
  guard('renderInput',kind=>can(kind));
  guard('openCostInput',()=>can('costs'));
  guard('renderCostInput',()=>can('costs'));
  guard('saveInputs',()=>execute(document.getElementById('inputModal')?.dataset.kind||'storage'));
  guard('saveCosts',()=>execute('costs'));
  guard('saveProjectionOverride',kind=>execute(kind));
  guard('setRevenueMonthStatus',kind=>execute(kind));
  guard('setInputProjectionCutoff',()=>execute(document.getElementById('inputModal')?.dataset.kind||'storage'));
  guard('setForecastMode',()=>execute('storage')&&execute('transport'));
  for(const name of ['addCostLine','resetCosts'])guard(name,()=>execute('costs'));
  guard('resetData',()=>access.admin);
  function lockControls(){
    document.querySelectorAll('.nav [data-tab]').forEach(b=>{b.hidden=!can(b.dataset.tab)});
    for(const section of Object.keys(labels)){
      const node=document.getElementById(section);
      if(node&&!can(section)){node.style.setProperty('display','none','important');node.dataset.accessDenied='true'}
    }
    document.querySelectorAll('[onclick]').forEach(b=>{
      const handler=b.getAttribute('onclick')||'';
      if(/openInput\(['"]storage/.test(handler)&&!can('storage'))b.hidden=true;
      if(/openInput\(['"]transport/.test(handler)&&!can('transport'))b.hidden=true;
      if(/openCostInput/.test(handler)&&!can('costs'))b.hidden=true;
    });
    document.querySelectorAll('.projectionEditor').forEach(input=>{input.disabled=!execute(input.dataset.kind)});
    const inputKind=document.getElementById('inputModal')?.dataset.kind||'storage';
    document.querySelectorAll('#inputModal input,#inputModal select,#inputModal .inputSaveBtn,#inputModal .forecastUnlock').forEach(input=>{
      if(!input.closest('.inputFilterBar')||input.id==='inputRealizedThrough'||input.id==='advanceEditedMonths')input.disabled=!execute(inputKind);
    });
    document.querySelectorAll('#costInputGrid input,#costModal .addCostInline,#costModal .accountRemove,#costModal .costEntryBar input,#costModal .costEntryBar select,#costModal .costEntryBar button,#costModal .inputSaveBtn,#costModal button[onclick*="saveCosts"],#costModal button[onclick*="resetCosts"],#costModal input[type="checkbox"]').forEach(input=>{input.disabled=!execute('costs')});
    document.querySelectorAll('.forecastControl select').forEach(input=>{input.disabled=!(execute('storage')&&execute('transport'))});
    if(access.profile==='VISUALIZADOR')document.getElementById('cloudSave').disabled=true;
    for(const panel of document.querySelectorAll('[data-access-denied]'))panel.style.setProperty('display','none','important');
  }
  lockControls();
  let scheduled=false;
  new MutationObserver(()=>{if(!scheduled){scheduled=true;queueMicrotask(()=>{scheduled=false;lockControls()})}}).observe(document.querySelector('.app'),{childList:true,subtree:true});
  const current=[...document.querySelectorAll('main>section.tab')].find(n=>getComputedStyle(n).display!=='none');
  if(!current||!can(current.id))originalGo.call(window,access.sections.find(s=>can(s))||'overview');
  const openOwnPassword=()=>window.openYalogPasswordSettings({identity,rpc,token,beforeChange:beforePasswordChange,onChanged:onPasswordChanged,onExit:onPasswordExit});
  const settingsButton=document.createElement('button');settingsButton.type='button';settingsButton.className='userSettingsButton';settingsButton.textContent='⚙ Configurações';settingsButton.onclick=openOwnPassword;
  document.querySelector('.nav').appendChild(settingsButton);
  const compactButton=settingsButton.cloneNode(true);compactButton.onclick=()=>settingsButton.onclick();document.querySelector('.cloudBar')?.insertBefore(compactButton,document.getElementById('cloudExit'));
  if(!access.admin&&!access.manager)return;

  const css=document.createElement('style');css.textContent=`
  #yalogUserSettings{width:min(900px,95vw);max-height:90vh;padding:0;border:1px solid #b8cbd0;border-radius:10px;background:#f5f6f2;color:#193f4c;font:14px/1.45 Segoe UI,Arial,sans-serif}#yalogUserSettings::backdrop{background:#071e2bc9}
  #yalogUserSettings header{display:flex;align-items:center;justify-content:space-between;padding:18px 22px;background:#153f4e;color:#fff}#yalogUserSettings h2{margin:0;font-size:21px}#yalogUserSettings .settingsBody{padding:20px}#yalogUserSettings button{cursor:pointer;padding:8px 12px;border:1px solid #b8c9cb;border-radius:5px;background:#fff;color:#173f4c;font:inherit}#yalogUserSettings button.primary{background:#e8752b;color:#fff;border-color:#e8752b;font-weight:700}#yalogUserSettings button:disabled{opacity:.55;cursor:default}#yalogUserSettings .settingsGrid{display:grid;grid-template-columns:1fr 1fr;gap:12px}#yalogUserSettings label{display:grid;gap:5px;font-size:12px;font-weight:650}#yalogUserSettings input,#yalogUserSettings select{width:100%;padding:10px;border:1px solid #b9cacf;border-radius:5px;background:#fff;color:#153f4d;font:14px Segoe UI,Arial}#yalogUserSettings input[type=checkbox]{width:auto;accent-color:#d86b25}#yalogUserSettings fieldset{margin:14px 0;padding:12px;border:1px solid #bdced0;border-radius:6px}#yalogUserSettings fieldset label,#yalogUserSettings .check{display:inline-flex;align-items:center;gap:8px;margin:5px 16px 5px 0}#yalogUserSettings .settingsActions{display:flex;gap:8px;margin:12px 0}#yalogUserSettings #settingsStatus{min-height:23px;margin:9px 0;color:#176948}#yalogUserSettings #settingsStatus.error{color:#a32f2a}#yalogUserSettings .settingsTable{overflow:auto;margin-top:18px}#yalogUserSettings table{min-width:650px;font-size:12px;border:1px solid #c3d1d2;border-radius:5px;background:#fff}#yalogUserSettings th{background:#153f4e;color:#fff;font-size:10px;text-align:left;padding:10px}#yalogUserSettings td{text-align:left;padding:10px;border-top:1px solid #d8e1e1;white-space:normal}#yalogUserSettings .settingsHelp{font-size:12px;color:#526e77;margin:12px 0}#yalogUserSettings [hidden]{display:none!important}@media(max-width:600px){#yalogUserSettings .settingsGrid{grid-template-columns:1fr}#yalogUserSettings .settingsBody{padding:12px}}@media print{#yalogUserSettings,.userSettingsButton{display:none!important}}
  `;document.head.appendChild(css);
  const dialog=document.createElement('dialog');dialog.id='yalogUserSettings';
  dialog.innerHTML=`<header><div><h2>Configurações</h2><small>Usuários e permissões desta empresa</small></div><button type="button" id="settingsClose" aria-label="Fechar configurações">Fechar</button></header><div class="settingsBody"><p class="settingsHelp">Cadastre um usuário novo ou vincule alguém que já utiliza a YALOG. O acesso será pelo Ecosystem da empresa.</p><fieldset><legend>Meu acesso</legend><button type="button" id="settingsMyPassword">Alterar minha senha</button><p class="settingsHelp">Esta opção altera somente a sua própria senha.</p></fieldset><h3>Gerenciar usuários</h3><form id="settingsUserForm"><label>Usuário<select id="settingsUser"><option value="">Cadastrar novo usuário</option></select></label><div class="settingsGrid" style="margin-top:12px"><label>Nome<input id="settingsName" maxlength="160" required autocomplete="off"></label><label>Login<input id="settingsLogin" minlength="3" maxlength="64" pattern="[a-zA-Z0-9][a-zA-Z0-9._-]{2,63}" required autocomplete="off"></label><label id="settingsPasswordLabel">Senha inicial<input type="password" id="settingsPassword" minlength="8" maxlength="128" autocomplete="new-password"></label><label id="settingsPasswordAgainLabel">Confirmar senha<input type="password" id="settingsPasswordAgain" minlength="8" maxlength="128" autocomplete="new-password"></label><label>Perfil<select id="settingsProfile"><option value="VISUALIZADOR">Visualizador — apenas consulta</option><option value="EXECUTOR">Executor — consulta e alteração</option>${access.admin?'<option value="GESTOR">Gestor — gerencia usuários</option>':''}</select></label></div><fieldset><legend>Áreas permitidas</legend>${Object.entries(labels).map(([key,label])=>`<label><input type="checkbox" name="settingsSection" value="${key}">${label}</label>`).join('')}</fieldset><label class="check" id="settingsActiveLabel"><input type="checkbox" id="settingsActive" checked>Acesso ativo neste módulo</label><p class="settingsHelp">Visão Geral mostra os indicadores consolidados. Custos e Despesas mostra as contas detalhadas. MASTER e Gestor gerenciam usuários conforme sua hierarquia.</p><div class="settingsActions"><button class="primary" id="settingsSubmit" type="submit">Salvar usuário</button><button type="button" id="settingsReset">Novo cadastro</button></div></form><fieldset id="settingsTargetActions" hidden><legend id="settingsTargetTitle">Ações do usuário selecionado</legend><div class="settingsActions"><button type="button" id="settingsTargetPassword">Redefinir senha</button><button type="button" id="settingsTargetBlock">Bloquear acesso</button><button type="button" id="settingsTargetDelete">Excluir do módulo</button></div></fieldset><p id="settingsStatus" role="status" aria-live="polite"></p><div class="settingsTable"><table><thead><tr><th>Nome / login</th><th>Perfil</th><th>Áreas</th><th>Status</th><th>Ações</th></tr></thead><tbody id="settingsUserList"></tbody></table></div></div>`;
  document.body.appendChild(dialog);
  document.getElementById('settingsMyPassword').onclick=openOwnPassword;
  const canEditUser=u=>!['MASTER','SUPER_ADMIN'].includes(u.central_role)&&u.profile!=='MASTER'&&(access.admin||(u.profile!=='GESTOR'&&u.central_role!=='GESTOR'&&(!u.linked||u.sections.every(can))));
  let users=[],editing=null,busy=false,formDirty=false;
  const $=id=>document.getElementById(id);
  const feedback=(text,error=false)=>{$('settingsStatus').textContent=text;$('settingsStatus').classList.toggle('error',error)};

  function reset(){$('settingsTargetActions').hidden=true;$('settingsActiveLabel').hidden=false;editing=null;formDirty=false;$('settingsUserForm').reset();$('settingsUser').value='';$('settingsName').disabled=false;$('settingsLogin').disabled=false;for(const id of ['settingsPassword','settingsPasswordAgain']){$(id).required=true;$(id).value=''}$('settingsPasswordLabel').hidden=false;$('settingsPasswordAgainLabel').hidden=false;$('settingsActive').checked=true;$('settingsSubmit').textContent='Cadastrar usuário'}
  function selectUser(login){const u=users.find(u=>u.login===login);if(!u){reset();return}if(!canEditUser(u))return;editing=u;formDirty=false;$('settingsTargetActions').hidden=!u.linked;$('settingsActiveLabel').hidden=u.linked;$('settingsTargetTitle').textContent='Ações de '+(u.name||u.login)+' ('+u.login+')';$('settingsTargetBlock').textContent=u.active?'Bloquear acesso':'Desbloquear acesso';$('settingsUser').value=u.login;$('settingsName').value=u.name||u.login;$('settingsLogin').value=u.login;$('settingsName').disabled=true;$('settingsLogin').disabled=true;for(const id of ['settingsPassword','settingsPasswordAgain']){$(id).required=false;$(id).value=''}$('settingsPasswordLabel').hidden=true;$('settingsPasswordAgainLabel').hidden=true;$('settingsProfile').value=u.profile==='GESTOR'?'GESTOR':u.profile==='VISUALIZADOR'?'VISUALIZADOR':'EXECUTOR';$('settingsActive').checked=u.linked?u.active:true;document.querySelectorAll('[name=settingsSection]').forEach(c=>{c.checked=can(c.value)&&u.sections.includes(c.value)});$('settingsSubmit').textContent=u.linked?'Salvar permissões':'Vincular usuário';$('settingsName').focus()}
  async function refresh(){const r=await rpc('faturamento_usuarios',{p_token:token()});users=r.users;const select=$('settingsUser');select.replaceChildren(new Option('Cadastrar novo usuário',''));$('settingsUserList').replaceChildren();for(const user of users){if(user.central_active&&canEditUser(user))select.add(new Option(`${user.name||user.login} (${user.login})${user.linked?'':' — vincular'}`,user.login));if(!user.linked)continue;const row=document.createElement('tr');const values=[`${user.name||user.login} (${user.login})`,user.profile==='MASTER'?'Administrador MASTER':user.profile==='GESTOR'?'Gestor':user.profile==='VISUALIZADOR'?'Visualizador':'Executor',user.sections.map(s=>labels[s]).join(', '),user.active&&user.central_active?'Ativo':'Inativo'];for(const text of values){const td=document.createElement('td');td.textContent=text;row.appendChild(td)}const action=document.createElement('td');if(canEditUser(user)){const b=document.createElement('button');b.type='button';b.textContent='Editar';b.onclick=()=>{selectUser(user.login);dialog.scrollTop=0};action.appendChild(b);}else action.textContent=user.profile==='GESTOR'?'Gestor • gerenciado pelo MASTER':'Plataforma YALOG';row.appendChild(action);$('settingsUserList').appendChild(row)}}
  $('settingsTargetPassword').onclick=()=>{if(editing&&canEditUser(editing)&&!busy)window.openYalogPasswordReset({user:editing,rpc,token})};
  async function userAction(action){
    if(busy||!editing||!editing.linked||!canEditUser(editing))return;
    const user=editing;
    if(formDirty&&!confirm('Descartar as alterações não salvas e continuar?'))return;
    if(action==='DELETE'&&!confirm('Excluir o acesso de '+user.login+' a este módulo? O cadastro na YALOG e os outros módulos serão mantidos.'))return;
    busy=true;for(const b of $('settingsTargetActions').querySelectorAll('button'))b.disabled=true;
    try{await rpc('faturamento_acao_usuario',{p_token:token(),p_action:action,p_login:user.login});reset();await refresh();feedback(action==='DELETE'?'Acesso excluído deste módulo.':action==='BLOCK'?'Acesso bloqueado.':'Acesso desbloqueado.')}
    catch(e){feedback(e.message,true)}finally{busy=false;for(const b of $('settingsTargetActions').querySelectorAll('button'))b.disabled=false}
  }
  $('settingsTargetBlock').onclick=()=>userAction(editing?.active?'BLOCK':'UNBLOCK');
  $('settingsTargetDelete').onclick=()=>userAction('DELETE');
  settingsButton.onclick=async()=>{dialog.showModal();reset();feedback('Carregando usuários…');try{await refresh();feedback('')}catch(e){feedback(e.message,true)}};

  const close=()=>{if(formDirty&&!confirm('Descartar as alterações ainda não salvas neste cadastro?'))return;dialog.close()};
  $('settingsClose').onclick=close;dialog.addEventListener('cancel',e=>{e.preventDefault();close()});
  document.querySelectorAll('[name=settingsSection]').forEach(c=>c.disabled=!can(c.value));
  $('settingsReset').onclick=reset;$('settingsUser').onchange=()=>selectUser($('settingsUser').value);
  $('settingsUserForm').addEventListener('input',()=>formDirty=true);
  $('settingsUserForm').onsubmit=async e=>{e.preventDefault();if(busy)return;const sections=[...document.querySelectorAll('[name=settingsSection]:checked')].map(c=>c.value);if(!sections.length){feedback('Selecione ao menos uma área de acesso.',true);return}let hash=null;if(!editing){const password=$('settingsPassword').value;if(password.length<8||password!==$('settingsPasswordAgain').value){feedback('As senhas devem ser iguais e ter pelo menos 8 caracteres.',true);return}hash=[...new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(password+'::yalog')))].map(v=>v.toString(16).padStart(2,'0')).join('')}
    busy=true;$('settingsSubmit').disabled=true;feedback('Salvando usuário…');try{await rpc('faturamento_gerenciar_usuario',{p_token:token(),p_action:editing?(editing.linked?'UPDATE':'LINK'):'CREATE',p_login:$('settingsLogin').value.trim().toLowerCase(),p_name:$('settingsName').value.trim(),p_hash:hash,p_profile:$('settingsProfile').value,p_sections:sections,p_active:$('settingsActive').checked});reset();await refresh();feedback('Usuário salvo. As novas permissões serão aplicadas ao entrar novamente no Ecosystem.')}catch(e){feedback(e.message,true)}finally{busy=false;$('settingsSubmit').disabled=false}};
};
