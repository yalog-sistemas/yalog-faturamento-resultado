'use strict';
window.installYalogCostEntry=function(){
 const grid=document.getElementById('costInputGrid'),bar=document.querySelector('#costModal .costLookupBar');if(!grid||!bar||grid.dataset.monthFilterInstalled)return;
 grid.dataset.monthFilterInstalled='true';
 const label=document.createElement('label');label.className='costMonthControl';label.textContent='Mês de lançamento';
 const select=document.createElement('select');select.id='costMonthFilter';select.setAttribute('aria-label','Filtrar mês dos custos e despesas');
 const names=['JAN','FEV','MAR','ABR','MAI','JUN','JUL','AGO','SET','OUT','NOV','DEZ'];
 for(const [value,text] of [['all','Todos os meses'],...names.map((m,i)=>[String(i),m])]){const option=document.createElement('option');option.value=value;option.textContent=text;select.appendChild(option)}
 select.value='all';label.appendChild(select);bar.insertBefore(label,bar.firstChild);
 function context(){
  const callout=grid.querySelector('.transportInputCallout'),note=grid.querySelector('.transportDreContext');if(!callout&&!note)return;
  let details=grid.querySelector('.costContextDetails');
  if(!details){details=document.createElement('details');details.className='costContextDetails';const summary=document.createElement('summary');summary.textContent='Detalhes da conferência';details.appendChild(summary);grid.insertBefore(details,grid.firstChild)}
  if(callout){for(const child of [...callout.children])if(child.tagName!=='LABEL')details.appendChild(child);if(!callout.children.length)callout.remove()}
  if(note&&!details.contains(note))details.appendChild(note);
 }
 function apply(){
  context();const chosen=select.value==='all'?null:Number(select.value);grid.classList.toggle('costSingleMonth',chosen!==null);
  for(const table of grid.querySelectorAll('table'))for(const row of table.querySelectorAll('tr')){
   const cells=[...row.children].filter(n=>n.tagName==='TH'||n.tagName==='TD');
   if(cells.length===14){
    for(let i=1;i<=12;i++){cells[i].hidden=chosen!==null&&i!==chosen+1;cells[i].classList.toggle('costMonthHidden',cells[i].hidden)}
    if(row.parentElement.tagName==='THEAD'){if(cells[13].textContent!=='Acumulado anual')cells[13].textContent='Acumulado anual';cells[13].title='Soma de janeiro a dezembro, mesmo ao filtrar um mês';}
   }else if(cells.length===1&&Number(cells[0].getAttribute('colspan'))>1){cells[0].setAttribute('colspan',chosen===null?'14':'3')}
  }
 }
 select.addEventListener('change',()=>{apply();grid.scrollLeft=0});
 const base=window.applyCostFilters;window.applyCostFilters=function(){const result=base?.apply(this,arguments);apply();return result};
 let pending=false;new MutationObserver(()=>{if(pending)return;pending=true;queueMicrotask(()=>{pending=false;apply()})}).observe(grid,{childList:true,subtree:true});
 window.addEventListener('beforeprint',()=>{grid.querySelectorAll('[colspan="3"]').forEach(cell=>cell.setAttribute('colspan','14'))});
 window.addEventListener('afterprint',apply);
 apply();
};
