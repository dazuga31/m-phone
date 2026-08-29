const state = { appId: 'mtablet.template', surface: 'tablet', language: 'en' };
const requestId = () => `tablet_${Date.now()}_${Math.random().toString(16).slice(2)}`;

const send = (action, payload = {}) => {
	const id = requestId();
	window.parent.postMessage({ type: 'mphone:sdk:request', requestId: id, action, payload }, '*');
	return id;
};

document.querySelectorAll('[data-page]').forEach((button) => {
	button.addEventListener('click', () => {
		const page = button.dataset.page;
		document.querySelectorAll('[data-page]').forEach((item) => item.classList.toggle('active', item === button));
		document.querySelectorAll('[data-page-panel]').forEach((panel) => panel.classList.toggle('active', panel.dataset.pagePanel === page));
	});
});

document.getElementById('ping').addEventListener('click', () => {
	document.getElementById('result').textContent = 'Waiting for Lua...';
	send('ping', { message: 'Tablet WebUI is ready' });
});

window.addEventListener('message', (event) => {
	const message = event.data || {};
	if (message.type === 'mphone:sdk:init') Object.assign(state, message);
	if (message.type === 'mphone:sdk:response' && message.appId === state.appId) {
		document.getElementById('result').textContent = message.ok ? (message.data?.message || 'Bridge connected.') : (message.error || 'Request failed.');
	}
});

window.parent.postMessage({ type: 'mphone:sdk:ready' }, '*');
