(function () {
  const pending = new Map();
  const listeners = new Map();
  let context = null;

  const emit = (name, payload) => {
    const handlers = listeners.get(name) || [];
    handlers.forEach((handler) => handler(payload));
  };

  window.addEventListener('message', (event) => {
    const message = event.data || {};
    if (message.type === 'mphone:sdk:init') {
      context = message;
      emit('ready', context);
    }
    if (message.type === 'mphone:sdk:response') {
      const operation = pending.get(message.requestId);
      if (operation) {
        pending.delete(message.requestId);
        clearTimeout(operation.timer);
        message.ok ? operation.resolve(message.data) : operation.reject(new Error(message.error || 'request_failed'));
      }
      emit('response', message);
    }
  });

  window.MPhone = Object.freeze({
    getContext: () => context,
    request(action, payload) {
      const id = `app_${Date.now()}_${Math.random().toString(16).slice(2)}`;
      return new Promise((resolve, reject) => {
        const timer = setTimeout(() => {
          pending.delete(id);
          reject(new Error('request_timeout'));
        }, 10000);
        pending.set(id, { resolve, reject, timer });
        parent.postMessage({ type: 'mphone:sdk:request', requestId: id, action, payload: payload || {} }, '*');
      });
    },
    close: () => parent.postMessage({ type: 'mphone:sdk:close' }, '*'),
    on(name, handler) {
      if (typeof handler !== 'function') return;
      listeners.set(name, [...(listeners.get(name) || []), handler]);
    },
    off(name, handler) {
      listeners.set(name, (listeners.get(name) || []).filter((entry) => entry !== handler));
    },
  });

  const ready = () => parent.postMessage({ type: 'mphone:sdk:ready' }, '*');
  document.readyState === 'loading' ? document.addEventListener('DOMContentLoaded', ready, { once: true }) : ready();
})();
