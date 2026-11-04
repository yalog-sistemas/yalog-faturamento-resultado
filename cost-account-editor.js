'use strict';
window.installYalogCostAccountEditor=function({identity}){
 if(window.yalogCostAccountEditorInstalled)return;window.yalogCostAccountEditorInstalled=true;
 const deduction='Deduções / Impostos',grid=document.getElementById('costInputGrid'),modal=document.getElementById('costModal');
 const norm=s=>String(s||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').trim().toLowerCase();
 const writable=()=>!!identity.access?.admin||(!['VISUALIZADOR','CONSULTA','LEITURA','VIEWER'].includes(String(identity.access?.profile).toUpperCase())&&identity.access?.sections?.includes('costs'));
 const cutoff=unit=>Math.max(0,Math.min(12,Number(getProjectionStart(unit==='transport'?'transport':'storage'))||0));
 const revenue=unit=>{const projected=unit==='transport'&&typeof calculateForecast==='function'?calculateForecast([], 'transport',0).values:null;return Array.from({length:12},(_,i)=>Number(unit==='transport'?(i>=cutoff(unit)&&projected?projected[i]:D.transport?.['2026']?.[i]):revenueUnit(unit,i))||0)};
 const validRate=p=>typeof p==='number'&&Number.isFinite(p)&&p>=0&&p<=100;
 function applyForecast(unit){
  if(!COSTS[unit])return;const rev=revenue(unit),start=cutoff(unit);
  for(const [cat,rows] of Object.entries(COSTS[unit]))if(Array.isArray(rows)&&cat!==deduction)for(const row of rows){const rule=row.forecastRule;if(rule?.kind!=='gross-revenue-percent'||!validRate(rule.percent)||!Array.isArray(row.values))continue;for(let i=start;i<12;i++)row.values[i]=-Math.round(Math.max(0,rev[i])*rule.percent)/100;}
 }
 function applyAll(){for(const unit of ['UBA','UDI','GYN','BSS','transport'])applyForecast(unit)}
 // Run before every calculation and save; a revenue change also updates projected commissions.
 for(const name of ['calcAll','renderResult','render']){const base=window[name];if(typeof base==='function')window[name]=function(...args){applyAll();const result=base.apply(this,args);if(name!=='calcAll')refreshAutomaticFields();return result}}
 function refreshAutomaticFields(){if(!grid)return;const unit=modal.dataset.unit;grid.querySelectorAll('input[data-cat]').forEach(field=>{const row=COSTS[unit]?.[field.dataset.cat]?.[Number(field.dataset.ri)],i=Number(field.dataset.i);if(row?.forecastRule?.kind==='gross-revenue-percent'&&i>=cutoff(unit)){field.value=Number(row.values[i]||0).toLocaleString('pt-BR',{minimumFractionDigits:2,maximumFractionDigits:2});const last=field.closest('tr')?.lastElementChild,text=row.values.reduce((s,v)=>s+(Number(v)||0),0).toLocaleString('pt-BR',{maximumFractionDigits:2});if(last&&last.textContent!==text)last.textContent=text}})}
 const baseSave=window.saveCosts;if(typeof baseSave==='function')window.saveCosts=function(...args){applyAll();refreshAutomaticFields();return baseSave.apply(this,args)};
 const baseUnit=window.calcUnit;if(typeof baseUnit==='function')window.calcUnit=function(unit,...args){applyForecast(unit);return baseUnit.call(this,unit,...args)};
 function mark(message){window.yalogCostsDirty=true;window.renderCostInput(modal.dataset.unit);window.renderResult();const status=document.getElementById('costStatus');if(status)status.textContent=message+' Salve os custos para gravar.'}
 function show(unit,cat,index){
  if(!writable())return;const item=COSTS[unit]?.[cat]?.[index];if(!item)return;
  const isDeduction=cat===deduction,canForecast=!isDeduction&&((unit==='transport'&&norm(item.label).includes('comiss'))||item.forecastRule?.kind==='gross-revenue-percent');
  let dialog=document.getElementById('costAccountDialog');if(!dialog){dialog=document.createElement('dialog');dialog.id='costAccountDialog';document.body.appendChild(dialog)}
  dialog.innerHTML='<header><div><small>CONTAS DE CUSTOS E DESPESAS</small><h2>Editar conta</h2></div><button type="button" id="accountClose">Fechar</button></header><div class="accountEditorBody"><p id="accountContext"></p><label>Nome / código da conta<input id="accountName" maxlength="180" autocomplete="off"></label><div id="accountCalculation"><label>Forma de lançamento<select id="accountMode"><option value="manual">Valores mensais manuais</option><option value="percent">Percentual do faturamento bruto — meses previstos</option></select></label><label id="accountPercentLabel">Percentual (%)<input id="accountPercent" type="text" inputmode="decimal" autocomplete="off"></label><p id="accountRateHelp"></p><div id="accountPreview"></div></div><p id="accountEditStatus" role="status" aria-live="polite"></p><div class="accountEditorActions"><button type="button" id="accountDelete">Excluir conta</button><button type="button" id="accountCancel">Cancelar</button><button type="button" id="accountSave">Aplicar alterações</button></div></div>';
  const $=id=>dialog.querySelector('#'+id);$('accountContext').textContent=(unit==='transport'?'Transporte':unit)+' • '+cat;$('accountName').value=item.label;
  const rev=revenue(unit),start=cutoff(unit),historical=rev.slice(0,start).reduce((a,b)=>a+b,0),used=(item.values||[]).slice(0,start).reduce((a,b)=>a+(Number(b)||0),0);
  let estimate=isDeduction?COSTS[unit]?.[deduction]?.[0]?.deductionPercent:item.forecastRule?.percent;if(!validRate(estimate))estimate=historical?Math.min(100,Math.abs(used)/historical*100):0;
  $('accountPercent').value=String(Number(estimate.toFixed(4))).replace('.',',');$('accountCalculation').hidden=!isDeduction&&!canForecast;
  $('accountMode').value=item.forecastRule?.kind==='gross-revenue-percent'?'percent':'manual';
  if(isDeduction){const configured=validRate(COSTS[unit]?.[deduction]?.[0]?.deductionPercent);$('accountMode').innerHTML=(configured?'':'<option value="manual">Manter lançamentos atuais</option>')+'<option value="percent">Percentual único de deduções — todos os meses</option>';$('accountMode').value=configured?'percent':'manual';}
  const parseRate=()=>{const text=$('accountPercent').value.trim().replace(/%$/,'').trim();if(!/^\d+(?:[.,]\d+)?$/.test(text))return null;const p=Number(text.replace(',','.'));return validRate(p)?p:null};
  function preview(){const percent=$('accountMode').value==='percent';$('accountPercentLabel').hidden=!percent;$('accountRateHelp').textContent=isDeduction&&percent?'Deduções mantêm a regra existente: percentual único sobre o faturamento bruto de todos os meses. Alterar esse percentual recalcula também os meses realizados.':percent?'Somente os meses previstos são calculados. Os valores dos meses realizados são preservados.':'Os valores atuais serão mantidos e poderão ser editados nos campos mensais.';const box=$('accountPreview');box.replaceChildren();if(!percent)return;const p=parseRate();if(p===null){box.textContent='Informe um percentual entre 0 e 100.';return}const from=isDeduction?0:start;if(from===12){box.textContent='Não há meses previstos em aberto. A regra será usada quando houver meses em previsão.';return}for(let i=from;i<12;i++){const line=document.createElement('div');line.textContent=months[i]+' • '+p.toLocaleString('pt-BR')+'% × '+rev[i].toLocaleString('pt-BR',{style:'currency',currency:'BRL'})+' = '+(-Math.round(Math.max(0,rev[i])*p)/100).toLocaleString('pt-BR',{style:'currency',currency:'BRL'});box.appendChild(line)}}
  const current=()=>COSTS[unit]?.[cat]?.[index]===item&&modal.dataset.unit===unit;
  $('accountSave').onclick=()=>{
   if(!writable()||!current())return $('accountEditStatus').textContent='A conta ou operação mudou. Feche e abra novamente.';
   const label=$('accountName').value.trim();if(label.length<2||label.length>180)return $('accountEditStatus').textContent='Informe um nome entre 2 e 180 caracteres.';
   if(COSTS[unit][cat].some(r=>r!==item&&norm(r.label)===norm(label)))return $('accountEditStatus').textContent='Já existe uma conta com esse nome nesta categoria.';
   const percent=(isDeduction||canForecast)&&$('accountMode').value==='percent',p=percent?parseRate():null;
   if(percent&&p===null)return $('accountEditStatus').textContent='Informe um percentual entre 0 e 100.';
   if(isDeduction&&percent&&COSTS[unit][deduction][0]?.deductionPercent!==p&&!confirm('Alterar o percentual único das deduções recalcula todos os meses desta operação, inclusive os realizados. Confirma?'))return;
   item.label=label;if(isDeduction){if(percent)COSTS[unit][deduction][0].deductionPercent=p;}else if(canForecast){if(percent)item.forecastRule={kind:'gross-revenue-percent',percent:p};else delete item.forecastRule;}
   applyForecast(unit);dialog.close();mark('Conta atualizada.');
  };
  $('accountDelete').onclick=()=>{if(!writable()||!current())return;if(!confirm('Excluir a conta “'+item.label+'”? Todos os seus valores mensais serão removidos.'))return;COSTS[unit][cat].splice(index,1);dialog.close();mark('Conta excluída.');};
  $('accountClose').onclick=$('accountCancel').onclick=()=>dialog.close();$('accountMode').onchange=preview;$('accountPercent').oninput=preview;preview();dialog.showModal();$('accountName').focus();
 }
 function decorate(){if(!grid)return;const unit=modal.dataset.unit;if(!COSTS[unit])return;
  grid.querySelectorAll('tr[data-cost-row]').forEach(tr=>{const input=tr.querySelector('input[data-cat]');if(!input)return;const cat=input.dataset.cat,index=Number(input.dataset.ri),item=COSTS[unit]?.[cat]?.[index];if(!item)return;let button=tr.querySelector('.accountRemove');if(!writable()){if(button)button.hidden=true;return}if(!button){button=document.createElement('button');tr.querySelector('td').appendChild(button)}button.type='button';button.className='accountRemove accountEdit';button.textContent='Editar conta';button.title='Editar nome, cálculo ou excluir esta conta';button.onclick=()=>show(unit,cat,index);
   if(cat===deduction)tr.querySelectorAll('input[data-cat]').forEach(field=>field.title='Calculado sobre o faturamento bruto. Use Editar conta para alterar o percentual.');
   if(cat!==deduction)tr.querySelectorAll('input[data-cat]').forEach(field=>{const automatic=item.forecastRule?.kind==='gross-revenue-percent'&&Number(field.dataset.i)>=cutoff(unit);field.readOnly=automatic;field.classList.toggle('accountForecastCalculated',automatic);if(automatic)field.title='Previsão: '+item.forecastRule.percent+'% do faturamento bruto. Use Editar conta.';});
  });
 }
 const baseRender=window.renderCostInput;window.renderCostInput=function(unit,...args){applyForecast(unit||modal.dataset.unit);const result=baseRender.call(this,unit,...args);decorate();return result};
 applyAll();if(COSTS[modal.dataset.unit])window.renderCostInput(modal.dataset.unit);window.renderResult();
};
