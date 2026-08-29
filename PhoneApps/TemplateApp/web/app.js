const status = document.getElementById('status');
const connection = document.getElementById('connection');
const output = document.getElementById('output');
const ping = document.getElementById('ping');
const clearOutput = document.getElementById('clear-output');
const surface = document.getElementById('surface');
const language = document.getElementById('language');
const sdkVersion = document.getElementById('sdk-version');

const renderOutput = (value) => {
  output.textContent = typeof value === 'string' ? value : JSON.stringify(value, null, 2);
};

MPhone.on('ready', (context) => {
  connection.dataset.state = 'ready';
  status.textContent = 'Connected';
  surface.textContent = context.surface || 'phone';
  language.textContent = context.language || 'en';
  sdkVersion.textContent = String(context.sdkVersion || context.version || '1');
  ping.disabled = false;
  renderOutput({ event: 'ready', context });
});

ping.addEventListener('click', async () => {
  ping.disabled = true;
  ping.dataset.loading = 'true';
  renderOutput('Sending request...');
  try {
    const result = await MPhone.request('ping', { message: 'Hello from Template App' });
    renderOutput(result);
  } catch (error) {
    connection.dataset.state = 'error';
    status.textContent = 'Request failed';
    renderOutput({ ok: false, error: String(error) });
  } finally {
    ping.disabled = false;
    ping.dataset.loading = 'false';
  }
});

clearOutput.addEventListener('click', () => renderOutput('No response yet.'));
