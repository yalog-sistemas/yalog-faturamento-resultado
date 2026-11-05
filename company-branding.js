'use strict';
window.installYalogCompanyBranding=function({identity,rpc,token,branding}){
 let current=branding,pendingLogo=branding.logo_data||null,imageRun=0,processing=false;
 const initials=name=>String(name).trim().split(/\s+/).slice(0,2).map(x=>x[0]||'').join('').toUpperCase();
 function logo(host,data,name){if(!host)return;host.replaceChildren();host.classList.add('companyLogo');if(data){const img=document.createElement('img');img.src=data;img.alt='Logotipo de '+name;host.appendChild(img)}else host.textContent=initials(name)}
 function apply(b){
  current=b;window.YALOG_COMPANY_BRAND=b;
  const title=document.querySelector('.top .brand b');if(title){title.textContent=b.display_name;title.title=b.display_name}
  document.querySelectorAll('.top .logo,#inputModal .modalHead .logo,#costModal .modalHead .logo').forEach(el=>logo(el,b.logo_data,b.display_name));
  const inputTitle=document.querySelector('#inputModal .modalHead h2'),costTitle=document.querySelector('#costModal .modalHead h2');if(inputTitle)inputTitle.textContent=b.display_name+' • Input de Faturamento';if(costTitle)costTitle.textContent=b.display_name+' • Custos e Despesas';
  const footer=document.getElementById('yalogInstitutionalFooter');if(footer)document.querySelector('.main')?.appendChild(footer);
  document.title=b.display_name+' | Faturamento e Resultado';
 }
 apply(branding);
 if(!identity.access?.admin)return;
 const body=document.querySelector('#yalogUserSettings .settingsBody');if(!body)return;
 const field=document.createElement('fieldset');field.className='companyBrandSettings';field.innerHTML='<legend>Identidade da empresa</legend><p>O nome e o logotipo aparecem para todos os usuários desta empresa. A marca YALOG permanece no rodapé.</p><div class="companyBrandPreview"></div><label>Nome no cabeçalho<input id="companyBrandName" maxlength="120" minlength="2" autocomplete="organization"></label><label>Logotipo da empresa<input id="companyBrandFile" type="file" accept="image/png,image/jpeg,image/webp"></label><small>PNG, JPG ou WebP de até 5 MB. A imagem será ajustada automaticamente.</small><div class="settingsActions"><button type="button" id="companyBrandSave" class="primary">Salvar identidade</button><button type="button" id="companyBrandRemove">Remover logotipo</button></div><p id="companyBrandStatus" role="status" aria-live="polite"></p>';
 body.insertBefore(field,body.firstChild);
 const name=field.querySelector('#companyBrandName'),file=field.querySelector('#companyBrandFile'),save=field.querySelector('#companyBrandSave'),status=field.querySelector('#companyBrandStatus'),preview=field.querySelector('.companyBrandPreview');
 name.value=current.display_name;const show=()=>logo(preview,pendingLogo,name.value||current.display_name);show();name.addEventListener('input',show);
 field.querySelector('#companyBrandRemove').onclick=()=>{imageRun++;pendingLogo=null;file.value='';processing=false;save.disabled=false;show();status.textContent='Salve para confirmar a remoção do logotipo.'};
 file.onchange=async()=>{
  const selected=file.files?.[0];if(!selected)return;const run=++imageRun;processing=true;save.disabled=true;status.textContent='Preparando logotipo…';
  let bitmap;
  try{if(!['image/png','image/jpeg','image/webp'].includes(selected.type)||selected.size>5*1024*1024)throw Error('Use PNG, JPG ou WebP de até 5 MB.');bitmap=await createImageBitmap(selected);if(bitmap.width*bitmap.height>40000000)throw Error('Imagem muito grande. Use uma versão menor.');const scale=Math.min(1,512/bitmap.width,256/bitmap.height),canvas=document.createElement('canvas');canvas.width=Math.max(1,Math.round(bitmap.width*scale));canvas.height=Math.max(1,Math.round(bitmap.height*scale));canvas.getContext('2d').drawImage(bitmap,0,0,canvas.width,canvas.height);const data=canvas.toDataURL('image/webp',.9);if(data.length>350000)throw Error('Imagem muito detalhada. Use um arquivo menor.');if(run!==imageRun)return;pendingLogo=data;show();status.textContent='Logotipo pronto. Clique em Salvar identidade para confirmar.'}
  catch(e){if(run===imageRun)status.textContent=e.message||'Não foi possível ler a imagem.'}
  finally{bitmap?.close();if(run===imageRun){processing=false;save.disabled=false}}
 };
 save.onclick=async()=>{if(processing)return;const displayName=name.value.trim();if(displayName.length<2||displayName.length>120){status.textContent='Informe um nome entre 2 e 120 caracteres.';return}save.disabled=true;status.textContent='Salvando identidade da empresa…';try{const result=await rpc('faturamento_salvar_identidade',{p_token:token(),p_display_name:displayName,p_logo_data:pendingLogo});if(!result?.ok)throw Error('Salvamento não confirmado.');apply(result.branding);name.value=current.display_name;status.textContent='Identidade salva para todos os usuários desta empresa.'}catch(e){status.textContent=e.message||'Não foi possível salvar.'}finally{save.disabled=false}};
};
