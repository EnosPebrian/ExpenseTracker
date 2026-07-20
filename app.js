const modal = document.querySelector('#modal');
const openModal = () => modal.classList.remove('hidden');
const closeModal = () => modal.classList.add('hidden');
document.querySelector('#quick-add').addEventListener('click', openModal);
document.querySelector('#quick-add-2').addEventListener('click', openModal);
document.querySelector('#close-modal').addEventListener('click', closeModal);
modal.addEventListener('click', e => { if (e.target === modal) closeModal(); });

const transactions = [
  {name:'Monthly groceries', category:'Food & dining', account:'Bank BCA', date:'Today, 09:42', isoDate:'2026-07-18', amount:'− Rp 842.500', cls:'expense', icon:'↙'},
  {name:'Client retainer — July', category:'Service income', account:'Bank BCA', date:'Yesterday', isoDate:'2026-07-17', amount:'+ Rp 7.500.000', cls:'income', icon:'↗'},
  {name:'Move to savings', category:'Transfer', account:'Bank BCA → Cash', date:'Jul 16, 2026', isoDate:'2026-07-16', amount:'Rp 1.000.000', cls:'', icon:'⇄'},
  {name:'Workspace subscription', category:'Software', account:'Jago', date:'Jul 15, 2026', isoDate:'2026-07-15', amount:'− Rp 249.000', cls:'expense', icon:'↙'}
];
function row(t,i){ return `<tr class="transaction-row" data-index="${i}"><td><div class="transaction-name"><span class="tx-icon ${t.cls==='income'?'income-icon':t.category==='Transfer'?'transfer-icon':'expense-icon'}">${t.icon}</span><div><strong>${t.name}</strong><small>${t.category}</small></div></div></td><td>${t.account}</td><td>${t.date}</td><td class="align-right amount ${t.cls}">${t.amount}</td></tr>`; }
const allRows = document.querySelector('#all-rows');
function renderTransactions(items=transactions){ allRows.innerHTML = items.map(t => row(t, transactions.indexOf(t))).join(''); }
renderTransactions();

document.querySelectorAll('[data-view]').forEach(btn => btn.addEventListener('click', () => {
  const view = btn.dataset.view;
  document.querySelectorAll('.page').forEach(p => p.classList.add('hidden'));
  document.querySelector(`#${view}-view`)?.classList.remove('hidden');
  document.querySelector('#page-title').textContent = view[0].toUpperCase()+view.slice(1);
  document.querySelectorAll('.nav-item').forEach(n => n.classList.toggle('active', n.dataset.view===view));
}));

document.querySelector('#save-transaction').addEventListener('click', () => {
  const type = document.querySelector('.type-tabs .active').dataset.type;
  const description = document.querySelector('#description').value.trim() || 'New expense';
  const amount = document.querySelector('#amount').value.trim() || 'Rp 0';
  const from = document.querySelector('#account-from').value;
  const isTransfer = type === 'Transfer';
  const category = isTransfer ? 'Transfer' : document.querySelector('#category').value;
  const account = isTransfer ? `${from} → ${document.querySelector('#account-to').value}` : from;
  const cls = type === 'Income' ? 'income' : type === 'Expense' ? 'expense' : '';
  const prefix = type === 'Income' ? '+ ' : type === 'Expense' ? '− ' : '';
  transactions.unshift({name:description, category, account, date:'Just now', isoDate:'2026-07-18', amount:`${prefix}${amount}`, cls, icon:type==='Income'?'↗':isTransfer?'⇄':'↙'});
  document.querySelector('#transaction-rows').insertAdjacentHTML('afterbegin', row(transactions[0],0));
  renderTransactions();
  document.querySelector('#description').value=''; document.querySelector('#amount').value=''; closeModal();
});

document.querySelector('#search').addEventListener('input', e => {
  const q = e.target.value.toLowerCase();
  renderTransactions(transactions.filter(t => `${t.name} ${t.category} ${t.account}`.toLowerCase().includes(q)));
});

const categories = {Expense:['Food & dining','Transport','Housing','Business','Software'],Income:['Sales','Service income','Salary','Investment income','Refund']};
function setType(type){
  document.querySelectorAll('.type-tabs button').forEach(t => t.classList.toggle('active',t.dataset.type===type));
  const transfer = type==='Transfer';
  document.querySelector('#account-label').childNodes[0].nodeValue = transfer?'From account':'Account';
  document.querySelector('#category-label').classList.toggle('hidden',transfer);
  document.querySelector('#account-to-label').classList.toggle('hidden',!transfer);
  if(!transfer) document.querySelector('#category').innerHTML=categories[type].map(c=>`<option>${c}</option>`).join('');
}
document.querySelectorAll('.type-tabs button').forEach(tab => tab.addEventListener('click',()=>setType(tab.dataset.type)));
setType('Expense');

function applyDateFilter(){
  const from=document.querySelector('#date-from').value, to=document.querySelector('#date-to').value;
  renderTransactions(transactions.filter(t=>(!from||t.isoDate>=from)&&(!to||t.isoDate<=to)));
}
document.querySelector('#date-from').addEventListener('change',applyDateFilter);
document.querySelector('#date-to').addEventListener('change',applyDateFilter);

const detailModal=document.querySelector('#detail-modal');
allRows.addEventListener('click',e=>{
  const tr=e.target.closest('.transaction-row'); if(!tr)return;
  const t=transactions[Number(tr.dataset.index)];
  document.querySelector('#detail-title').textContent=t.name;
  document.querySelector('#detail-amount').textContent=t.amount;
  document.querySelector('#detail-type').textContent=t.category==='Transfer'?'Transfer':t.cls==='income'?'Income':'Expense';
  document.querySelector('#detail-date').textContent=t.date;
  document.querySelector('#detail-account').textContent=t.account;
  document.querySelector('#detail-category').textContent=t.category;
  detailModal.classList.remove('hidden');
});
document.querySelector('#close-detail').addEventListener('click',()=>detailModal.classList.add('hidden'));
detailModal.addEventListener('click',e=>{if(e.target===detailModal)detailModal.classList.add('hidden')});
