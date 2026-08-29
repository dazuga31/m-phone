const state=document.getElementById('state');
const title=document.getElementById('title');
const value=document.getElementById('value');
const surface=document.getElementById('surface');
const refresh=document.getElementById('refresh');

async function load(){
	state.textContent='SYNCING';
	try{
		const result=await MPhoneWidget.request('refresh',{value:'HELIX Tablet'});
		title.textContent=result.title||'Tablet widget connected';
		value.textContent=result.value||'Ready';
		surface.textContent=(result.surface||'tablet').toUpperCase();
		state.textContent='READY';
	}catch(error){
		state.textContent='OFFLINE';
		value.textContent=String(error);
	}
}

MPhoneWidget.on('ready',context=>{
	document.body.dataset.variant=context.size||'wide';
	document.body.dataset.surface=context.surface||'tablet';
	load();
});

refresh.addEventListener('click',load);
