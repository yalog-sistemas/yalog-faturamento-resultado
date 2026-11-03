'use strict';
window.yalogHashPassword=async password=>[...new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(password+'::yalog')))].map(v=>v.toString(16).padStart(2,'0')).join('');

function yalogPasswordStyles(){
 if(document.getElementById('yalogPasswordStyles'))return;
 const style=document.createElement('style');style.id='yalogPasswordStyles';style.textContent=`
 .yalogPasswordDialog{width:min(500px,94vw);max-height:90vh;overflow:auto;border:1px solid #b7cbd0;border-radius:10px;padding:22px;background:#f7f8f4;color:#163e4b;font:14px/1.5 Segoe UI,Arial,sans-serif}.yalogPasswordDialog::backdrop{background:#071e2bcc}.yalogPasswordDialog h2{margin:0 0 8px}.yalogPasswordDialog label{display:grid;gap:5px;margin:14px 0;font-weight:650}.yalogPasswordDialog input{padding:10px;border:1px solid #afc4c9;border-radius:5px;color:#153f4d;font:14px Segoe UI,Arial;min-width:0;width:100%;box-sizing:border-box}.yalogPasswordDialog button{padding:9px 13px;margin:4px 7px 4px 0;border:1px solid #afc4c9;border-radius:5px;background:#fff;color:#163f4c;cursor:pointer;font:inherit}.yalogPasswordDialog button.primary{background:#e8752b;color:#fff;border-color:#e8752b;font-weight:700}.yalogPasswordDialog button:disabled{opacity:.55;cursor:default}.yalogPasswordDialog .help{font-size:12px;color:#526d76}.yalogPasswordDialog [role=status]{min-height:23px;color:#146845}.yalogPasswordDialog [role=status].error{color:#a42d29}.yalogPasswordDialog [hidden]{display:none!important}.yalogPasswordDialog .temporary{background:#fff6df;border:1px solid #dabf7d;border-radius:6px;padding:12px;margin:12px 0}.yalogPasswordDialog .temporary input{font-family:Consolas,monospace;font-size:17px}@media print{.yalogPasswordDialog{display:none!important}}`;
 document.head.appendChild(style);
}

window.openYalogPasswordSettings=function({identity,rpc,token,beforeChange,onChanged,onExit,force=false}){
 yalogPasswordStyles();document.getElementById('yalogMyPassword')?.remove();
 const dialog=document.createElement('dialog');dialog.id='yalogMyPassword';dialog.className='yalogPasswordDialog';
 dialog.innerHTML=`<h2>${force?'Troque sua senha temporária':'Minha senha'}</h2><p id="passwordIdentity"></p><p class="help">Esta senha é a do seu login YALOG e vale para os módulos que você utiliza. Depois da alteração, será necessário entrar novamente.</p><form id="myPasswordForm"><label>Senha atual<input id="myCurrentPassword" type="password" autocomplete="current-password" required maxlength="128"></label><label>Nova senha<input id="myNewPassword" type="password" autocomplete="new-password" required minlength="8" maxlength="128"></label><label>Confirmar nova senha<input id="myConfirmPassword" type="password" autocomplete="new-password" required minlength="8" maxlength="128"></label><p class="help">Use pelo menos 8 caracteres e uma senha diferente da atual.</p><button type="submit" class="primary" id="myPasswordSave">Alterar minha senha</button><button type="button" id="myPasswordClose">${force?'Voltar ao acesso':'Cancelar'}</button></form><p id="myPasswordStatus" role="status" aria-live="polite"></p>`;
 document.body.appendChild(dialog);const $=id=>document.getElementById(id);$('passwordIdentity').textContent=identity.nome?`${identity.nome} (${identity.login})`:identity.login;
 const feedback=(text,error=false)=>{$('myPasswordStatus').textContent=text;$('myPasswordStatus').classList.toggle('error',error)};
 const clear=()=>{for(const input of dialog.querySelectorAll('input'))input.value=''};
 let busy=false;
 $('myPasswordClose').onclick=()=>{if(busy)return;clear();dialog.close();dialog.remove();if(force)onExit?.()};
 dialog.addEventListener('cancel',e=>{e.preventDefault();if(!force&&!busy)$('myPasswordClose').click()});
 $('myPasswordForm').onsubmit=async event=>{event.preventDefault();if(busy)return;const current=$('myCurrentPassword').value,next=$('myNewPassword').value;
  if(next.length<8||next!==$('myConfirmPassword').value||next===current){feedback('Confirme uma senha nova com pelo menos 8 caracteres, diferente da atual.',true);return}
  busy=true;$('myPasswordSave').disabled=true;feedback('Alterando senha…');
  try{await beforeChange?.();const currentHash=await window.yalogHashPassword(current),newHash=await window.yalogHashPassword(next);const response=await rpc('faturamento_alterar_senha',{p_token:token(),p_current_hash:currentHash,p_new_hash:newHash});if(!response.ok)throw Error('Alteração não confirmada');clear();dialog.close();dialog.remove();onChanged?.()}
  catch(error){feedback(error.message||'Não foi possível alterar a senha.',true)}
  finally{busy=false;const button=document.getElementById('myPasswordSave');if(button)button.disabled=false}
 };
 dialog.showModal();$('myCurrentPassword').focus();return dialog;
};

window.openYalogPasswordReset=function({user,rpc,token}){
 yalogPasswordStyles();document.getElementById('yalogResetPassword')?.remove();
 const dialog=document.createElement('dialog');dialog.id='yalogResetPassword';dialog.className='yalogPasswordDialog';
 dialog.innerHTML=`<h2>Redefinir senha</h2><p id="resetPasswordIdentity"></p><p class="help">Será gerada uma senha temporária para o login YALOG deste usuário. As sessões anteriores serão encerradas e a troca será obrigatória ao entrar novamente neste módulo.</p><button type="button" class="primary" id="resetPasswordGenerate">Gerar senha temporária</button><button type="button" id="resetPasswordClose">Fechar</button><div class="temporary" id="temporaryPasswordPanel" hidden><label>Senha temporária<input id="temporaryPasswordValue" readonly autocomplete="off"></label><button type="button" id="temporaryPasswordCopy">Copiar senha</button><p class="help">Copie e envie ao usuário por um canal de sua confiança. Esta senha deixa de aparecer ao fechar esta janela.</p></div><p id="resetPasswordStatus" role="status" aria-live="polite"></p>`;
 document.body.appendChild(dialog);const $=id=>document.getElementById(id);$('resetPasswordIdentity').textContent=`${user.name||user.login} (${user.login})`;
 const feedback=(text,error=false)=>{$('resetPasswordStatus').textContent=text;$('resetPasswordStatus').classList.toggle('error',error)};
 let busy=false;
 const close=()=>{if(busy)return;$('temporaryPasswordValue').value='';dialog.close();dialog.remove()};
 $('resetPasswordClose').onclick=close;dialog.addEventListener('cancel',e=>{e.preventDefault();close()});
 $('resetPasswordGenerate').onclick=async()=>{if(busy)return;busy=true;$('resetPasswordGenerate').disabled=true;feedback('Gerando nova senha…');
  try{const alphabet='ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';const bytes=crypto.getRandomValues(new Uint8Array(16));const temporary='Yl!'+[...bytes].map(b=>alphabet[b%alphabet.length]).join('')+'9a';const hash=await window.yalogHashPassword(temporary);const result=await rpc('faturamento_redefinir_senha',{p_token:token(),p_login:user.login,p_new_hash:hash});if(!result.ok)throw Error('Redefinição não confirmada');$('temporaryPasswordValue').value=temporary;$('temporaryPasswordPanel').hidden=false;feedback('Senha redefinida. O usuário deverá entrar novamente e escolher a própria senha.')}
  catch(error){feedback(error.message||'Não foi possível redefinir a senha.',true);$('resetPasswordGenerate').disabled=false}
  finally{busy=false}
 };
 $('temporaryPasswordCopy').onclick=async()=>{try{await navigator.clipboard.writeText($('temporaryPasswordValue').value);feedback('Senha copiada.')}catch{$('temporaryPasswordValue').focus();$('temporaryPasswordValue').select();feedback('Selecione a senha e copie com Ctrl+C.')}};
 dialog.showModal();return dialog;
};
